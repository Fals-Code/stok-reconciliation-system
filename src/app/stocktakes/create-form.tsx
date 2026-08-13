"use client";

import {
  useEffect,
  useRef,
  useState,
} from "react";
import { useFormStatus } from "react-dom";

import { createStocktakeAction } from "@/app/stocktakes/actions";
import {
  Alert,
  Input,
  Select,
  Textarea,
} from "@/components/ui";
import type {
  StocktakeCreateOptions,
  StocktakeScopeMode,
} from "@/lib/stocktakes/types";

const DRAFT_STORAGE_KEY =
  "stocktake-create-draft-v1";

type StoredDraft = {
  title: string;
  stocktakeTypeCode: string;
  visibilityCode: string;
  scopeMode: StocktakeScopeMode;
  bucketCodes: string[];
  productIds: string[];
  batchIds: string[];
  plannedAt: string;
  includeZeroSystemBalance: boolean;
  includeInactiveWithBalance: boolean;
  includeBlockedBatches: boolean;
  includeExpiredBatches: boolean;
  note: string;
};

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      className="inline-flex min-h-[var(--ui-control-height)] shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-5 text-sm font-semibold text-ui-text-on-primary disabled:cursor-not-allowed disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "Membuat sesi..." : "Buat Sesi"}
    </button>
  );
}

function readStoredDraft() {
  try {
    const raw = window.sessionStorage.getItem(
      DRAFT_STORAGE_KEY,
    );

    if (!raw) return null;

    return JSON.parse(raw) as StoredDraft;
  } catch {
    return null;
  }
}

function saveDraft(form: HTMLFormElement) {
  const data = new FormData(form);

  const draft: StoredDraft = {
    title: String(data.get("title") ?? ""),
    stocktakeTypeCode: String(
      data.get("stocktakeTypeCode") ?? "FULL",
    ),
    visibilityCode: String(
      data.get("visibilityCode") ?? "BLIND",
    ),
    scopeMode: String(
      data.get("scopeMode") ??
        "ALL_ACTIVE_INVENTORY",
    ) as StocktakeScopeMode,
    bucketCodes: data
      .getAll("bucketCodes")
      .map(String),
    productIds: data
      .getAll("productIds")
      .map(String),
    batchIds: data
      .getAll("batchIds")
      .map(String),
    plannedAt: String(data.get("plannedAt") ?? ""),
    includeZeroSystemBalance:
      data.get("includeZeroSystemBalance") === "on",
    includeInactiveWithBalance:
      data.get("includeInactiveWithBalance") === "on",
    includeBlockedBatches:
      data.get("includeBlockedBatches") === "on",
    includeExpiredBatches:
      data.get("includeExpiredBatches") === "on",
    note: String(data.get("note") ?? ""),
  };

  window.sessionStorage.setItem(
    DRAFT_STORAGE_KEY,
    JSON.stringify(draft),
  );
}

function setNamedChecks(
  form: HTMLFormElement,
  name: string,
  values: string[],
) {
  const selected = new Set(values);

  form
    .querySelectorAll<HTMLInputElement>(
      `input[name="${name}"]`,
    )
    .forEach((input) => {
      input.checked = selected.has(input.value);
    });
}

export function StocktakeCreateForm({
  idempotencyKey,
  options,
  shouldRestoreDraft,
}: {
  idempotencyKey: string;
  options: StocktakeCreateOptions;
  shouldRestoreDraft: boolean;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [selectedScope, setSelectedScope] =
    useState<StocktakeScopeMode>(
      "ALL_ACTIVE_INVENTORY",
    );
  const [validationMessage, setValidationMessage] =
    useState("");

  useEffect(() => {
    if (!shouldRestoreDraft) {
      window.sessionStorage.removeItem(
        DRAFT_STORAGE_KEY,
      );
      return;
    }

    const draft = readStoredDraft();
    const form = formRef.current;

    if (!draft || !form) return;

    const setValue = (
      name: string,
      value: string,
    ) => {
      const element =
        form.elements.namedItem(name);

      if (
        element instanceof HTMLInputElement ||
        element instanceof HTMLSelectElement ||
        element instanceof HTMLTextAreaElement
      ) {
        element.value = value;
      }
    };

    setValue("title", draft.title);
    setValue(
      "stocktakeTypeCode",
      draft.stocktakeTypeCode,
    );
    setValue(
      "visibilityCode",
      draft.visibilityCode,
    );
    setValue("plannedAt", draft.plannedAt);
    setValue("note", draft.note);

    setSelectedScope(draft.scopeMode);

    setNamedChecks(
      form,
      "bucketCodes",
      draft.bucketCodes,
    );
    setNamedChecks(
      form,
      "productIds",
      draft.productIds,
    );
    setNamedChecks(
      form,
      "batchIds",
      draft.batchIds,
    );

    const optionalChecks: Array<
      [string, boolean]
    > = [
      [
        "includeZeroSystemBalance",
        draft.includeZeroSystemBalance,
      ],
      [
        "includeInactiveWithBalance",
        draft.includeInactiveWithBalance,
      ],
      [
        "includeBlockedBatches",
        draft.includeBlockedBatches,
      ],
      [
        "includeExpiredBatches",
        draft.includeExpiredBatches,
      ],
    ];

    for (const [name, checked] of optionalChecks) {
      const input = form.elements.namedItem(
        name,
      );

      if (input instanceof HTMLInputElement) {
        input.checked = checked;
      }
    }
  }, [shouldRestoreDraft]);

  function validateAndRemember(
    event: React.FormEvent<HTMLFormElement>,
  ) {
    const form = event.currentTarget;
    const data = new FormData(form);
    const bucketCodes =
      data.getAll("bucketCodes");
    const productIds =
      data.getAll("productIds");
    const batchIds =
      data.getAll("batchIds");

    let message = "";

    if (bucketCodes.length === 0) {
      message =
        "Pilih minimal satu kondisi fisik yang akan dihitung.";
    } else if (
      selectedScope === "PRODUCTS" &&
      productIds.length === 0
    ) {
      message =
        "Pilih minimal satu produk yang akan dihitung.";
    } else if (
      selectedScope === "BATCHES" &&
      batchIds.length === 0
    ) {
      message =
        "Pilih minimal satu Kode Batch yang akan dihitung.";
    }

    if (message) {
      event.preventDefault();
      setValidationMessage(message);
      return;
    }

    setValidationMessage("");
    saveDraft(form);
  }

  return (
    <form
      action={createStocktakeAction}
      className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
      onSubmit={validateAndRemember}
      ref={formRef}
    >
      <input
        name="idempotencyKey"
        type="hidden"
        value={idempotencyKey}
      />

      {validationMessage ? (
        <Alert
          className="mb-5"
          title="Periksa isian"
          tone="warning"
        >
          {validationMessage}
        </Alert>
      ) : null}

      <div className="grid gap-5 sm:grid-cols-2">
        <label className="grid gap-2 text-sm font-semibold text-ui-text">
          Nama hitung stok
          <Input
            autoComplete="off"
            name="title"
            placeholder="Contoh: Opname akhir hari"
            required
          />
        </label>

        <label className="grid gap-2 text-sm font-semibold text-ui-text">
          Jenis hitung
          <Select
            defaultValue="FULL"
            name="stocktakeTypeCode"
          >
            <option value="FULL">
              Hitung Lengkap
            </option>
            <option value="CYCLE">
              Hitung Berkala
            </option>
            <option value="AD_HOC">
              Hitung Khusus
            </option>
          </Select>
          <span className="text-xs font-normal leading-5 text-ui-text-muted">
            Jenis pekerjaan ini terpisah dari bagian stok yang dipilih.
          </span>
        </label>

        <label className="grid gap-2 text-sm font-semibold text-ui-text sm:max-w-md">
          Cara hitung
          <Select
            defaultValue="BLIND"
            name="visibilityCode"
          >
            <option value="BLIND">
              Tanpa melihat catatan
            </option>
            <option value="NON_BLIND">
              Dengan melihat catatan
            </option>
          </Select>
          <span className="text-xs font-normal leading-5 text-ui-text-muted">
            Disarankan tanpa melihat catatan agar hasil fisik tidak dipengaruhi angka sistem.
          </span>
        </label>
      </div>

      <section
        aria-labelledby="stocktake-scope-heading"
        className="mt-6 border-t border-ui-border pt-5"
      >
        <h2
          className="text-base font-semibold text-ui-text"
          id="stocktake-scope-heading"
        >
          Yang dihitung
        </h2>

        <div className="mt-4 max-w-md">
          <label className="grid gap-2 text-sm font-semibold text-ui-text">
            Bagian stok
            <Select
              name="scopeMode"
              onChange={(event) => {
                setSelectedScope(
                  event.target
                    .value as StocktakeScopeMode,
                );
                setValidationMessage("");
              }}
              value={selectedScope}
            >
              <option value="ALL_ACTIVE_INVENTORY">
                Semua produk aktif
              </option>
              <option value="PRODUCTS">
                Produk tertentu
              </option>
              <option value="BATCHES">
                Kode Batch tertentu
              </option>
            </Select>
          </label>
        </div>

        <fieldset className="mt-5">
          <legend className="text-sm font-semibold text-ui-text">
            Kondisi fisik
          </legend>
          <div className="mt-2 flex flex-wrap gap-x-6 gap-y-2 text-sm text-ui-text">
            <label className="flex min-h-8 items-center gap-2">
              <input
                defaultChecked
                name="bucketCodes"
                type="checkbox"
                value="SELLABLE"
              />
              Layak Dijual
            </label>
            <label className="flex min-h-8 items-center gap-2">
              <input
                defaultChecked
                name="bucketCodes"
                type="checkbox"
                value="QUARANTINE"
              />
              Ditahan
            </label>
            <label className="flex min-h-8 items-center gap-2">
              <input
                defaultChecked
                name="bucketCodes"
                type="checkbox"
                value="DAMAGED"
              />
              Rusak
            </label>
          </div>
        </fieldset>

        {selectedScope === "PRODUCTS" ? (
          <fieldset className="mt-5">
            <legend className="text-sm font-semibold text-ui-text">
              Pilih produk
            </legend>

            {options.products.length ? (
              <div className="mt-3 max-h-64 overflow-y-auto rounded-[var(--ui-radius-md)] border border-ui-border">
                {options.products.map(
                  (product) => (
                    <label
                      className="flex min-h-11 items-center gap-3 border-b border-ui-border px-4 py-2 text-sm text-ui-text last:border-b-0"
                      key={product.product_id}
                    >
                      <input
                        name="productIds"
                        type="checkbox"
                        value={product.product_id}
                      />
                      <span>
                        <span className="font-semibold">
                          {product.sku}
                        </span>
                        {" \u00B7 "}
                        {product.name}
                      </span>
                    </label>
                  ),
                )}
              </div>
            ) : (
              <p className="mt-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-sm text-ui-text-muted">
                Belum ada produk yang dapat dipilih.
              </p>
            )}
          </fieldset>
        ) : null}

        {selectedScope === "BATCHES" ? (
          <fieldset className="mt-5">
            <legend className="text-sm font-semibold text-ui-text">
              Pilih Kode Batch
            </legend>

            {options.batches.length ? (
              <div className="mt-3 max-h-64 overflow-y-auto rounded-[var(--ui-radius-md)] border border-ui-border">
                {options.batches.map(
                  (batch) => (
                    <label
                      className="flex min-h-11 items-center gap-3 border-b border-ui-border px-4 py-2 text-sm text-ui-text last:border-b-0"
                      key={batch.batch_id}
                    >
                      <input
                        name="batchIds"
                        type="checkbox"
                        value={batch.batch_id}
                      />
                      <span>
                        <span className="font-semibold">
                          {batch.batch_code}
                        </span>
                        {" \u00B7 "}
                        {batch.product_name}
                      </span>
                    </label>
                  ),
                )}
              </div>
            ) : (
              <p className="mt-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-sm text-ui-text-muted">
                Belum ada Kode Batch yang dapat dipilih.
              </p>
            )}
          </fieldset>
        ) : null}

        <details className="mt-5 border-t border-ui-border pt-4">
          <summary className="cursor-pointer text-sm font-semibold text-ui-text">
            Pilihan tambahan
            <span className="ml-2 font-normal text-ui-text-muted">
              Untuk kondisi khusus saja
            </span>
          </summary>

          <div className="mt-4 grid gap-4 text-sm text-ui-text sm:grid-cols-2">
            <label className="grid gap-2 font-semibold">
              Rencana mulai
              <Input
                name="plannedAt"
                type="datetime-local"
              />
              <span className="text-xs font-normal leading-5 text-ui-text-muted">
                Opsional.
              </span>
            </label>

            <div className="grid gap-3 sm:pt-7">
              <label className="flex items-start gap-2">
                <input
                  className="mt-0.5"
                  name="includeZeroSystemBalance"
                  type="checkbox"
                />
                Sertakan lokasi dengan catatan sistem nol
              </label>
              <label className="flex items-start gap-2">
                <input
                  className="mt-0.5"
                  name="includeInactiveWithBalance"
                  type="checkbox"
                />
                Sertakan produk tidak aktif yang masih bersaldo
              </label>
              <label className="flex items-start gap-2">
                <input
                  className="mt-0.5"
                  name="includeBlockedBatches"
                  type="checkbox"
                />
                Sertakan Kode Batch ditahan
              </label>
              <label className="flex items-start gap-2">
                <input
                  className="mt-0.5"
                  name="includeExpiredBatches"
                  type="checkbox"
                />
                Sertakan Kode Batch kedaluwarsa
              </label>
            </div>
          </div>
        </details>
      </section>

      <label className="mt-5 grid gap-2 border-t border-ui-border pt-5 text-sm font-semibold text-ui-text">
        Catatan (opsional)
        <Textarea
          name="note"
          placeholder="Contoh: fokus rak utama."
          rows={2}
        />
      </label>

      <div className="mt-5 flex flex-col gap-3 border-t border-ui-border pt-4 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-sm text-ui-text-muted">
          Membuat sesi tidak mengubah stok.
        </p>
        <SubmitButton />
      </div>
    </form>
  );
}