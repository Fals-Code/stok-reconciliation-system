"use client";

import {
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { useFormStatus } from "react-dom";

import { Button, StatusBadge } from "@/components/ui";

type ReviewKind =
  | "receipt"
  | "inspection"
  | "lost"
  | "late-arrival";

type ReviewLine = {
  key: string;
  productSku: string;
  detail: string;
  quantity: number;
};

type ReviewState = {
  eligible: boolean;
  title: string;
  stockImpact: string;
  note: string;
  lines: ReviewLine[];
  blockers: string[];
};

function number(value: FormDataEntryValue | null) {
  const parsed = Number(String(value ?? "0"));
  return Number.isSafeInteger(parsed) ? parsed : Number.NaN;
}

function checked(
  form: HTMLFormElement,
  name: string,
) {
  return Array.from(
    form.querySelectorAll<HTMLInputElement>(
      `input[type="checkbox"][name="${name}"]:checked`,
    ),
  );
}

function formData(form: HTMLFormElement) {
  return new FormData(form);
}

function amount(value: number) {
  return new Intl.NumberFormat("id-ID").format(value);
}

function receiptReview(form: HTMLFormElement): ReviewState {
  const data = formData(form);
  const selected = checked(form, "receiptLineKey");
  const blockers: string[] = [];
  const totals = new Map<string, number>();

  const lines = selected.map((input) => {
    const key = input.value;
    const quantity = number(
      data.get(`receiptQuantity_${key}`),
    );
    const returnItemId = input.dataset.returnItemId ?? "";
    const pending = Number(input.dataset.pending ?? "0");

    totals.set(
      returnItemId,
      (totals.get(returnItemId) ?? 0) + quantity,
    );

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} memiliki jumlah kedatangan yang tidak valid.`,
      );
    }

    if (
      Number.isSafeInteger(pending) &&
      pending > 0 &&
      (totals.get(returnItemId) ?? 0) > pending
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} melebihi sisa jumlah yang masih menunggu datang.`,
      );
    }

    const batch = input.dataset.batchCode;
    const expiry = input.dataset.expiryDate;
    const verified = input.dataset.verified === "true";

    return {
      key,
      productSku: input.dataset.productSku ?? "Item retur",
      detail: verified
        ? `Batch asal ${batch ?? "-"}; kedaluwarsa ${expiry ?? "-"}`
        : "Batch asal belum terverifikasi",
      quantity,
    };
  });

  if (!selected.length) {
    blockers.push("Pilih minimal satu item yang benar-benar datang.");
  }

  const total = lines.reduce(
    (sum, line) =>
      sum + (Number.isFinite(line.quantity) ? line.quantity : 0),
    0,
  );

  return {
    eligible: blockers.length === 0,
    title: "Periksa Kedatangan",
    stockImpact: "Stok tidak berubah",
    note:
      "Kedatangan hanya mencatat barang yang tiba. Jika batch asal terverifikasi, sistem menyimpan asal kiriman untuk jejak audit.",
    lines,
    blockers,
  };
}

function inspectionReview(
  form: HTMLFormElement,
): ReviewState {
  const data = formData(form);
  const selected = checked(
    form,
    "inspectionReceiptLineId",
  );
  const blockers: string[] = [];

  const lines = selected.map((input) => {
    const id = input.value;
    const sellable = number(
      data.get(`sellableQuantity_${id}`),
    );
    const damaged = number(
      data.get(`damagedQuantity_${id}`),
    );
    const pending = Number(input.dataset.pending ?? "0");
    const verified = input.dataset.verified === "true";
    const total = sellable + damaged;

    if (
      !Number.isSafeInteger(sellable) ||
      sellable < 0 ||
      !Number.isSafeInteger(damaged) ||
      damaged < 0 ||
      total <= 0
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} harus memiliki jumlah layak jual atau rusak lebih dari nol.`,
      );
    }

    if (
      Number.isSafeInteger(pending) &&
      total > pending
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} melebihi jumlah yang belum diperiksa.`,
      );
    }

    if (sellable > 0 && !verified) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} belum memiliki batch asal terverifikasi sehingga belum dapat ditandai layak jual.`,
      );
    }

    return {
      key: id,
      productSku: input.dataset.productSku ?? "Item retur",
      detail:
        `${amount(sellable)} layak jual; ` +
        `${amount(damaged)} rusak`,
      quantity: total,
    };
  });

  if (!selected.length) {
    blockers.push(
      "Pilih minimal satu kedatangan yang akan diperiksa.",
    );
  }

  const sellableTotal = selected.reduce(
    (sum, input) =>
      sum +
      Math.max(
        0,
        number(
          data.get(
            `sellableQuantity_${input.value}`,
          ),
        ) || 0,
      ),
    0,
  );
  const damagedTotal = selected.reduce(
    (sum, input) =>
      sum +
      Math.max(
        0,
        number(
          data.get(
            `damagedQuantity_${input.value}`,
          ),
        ) || 0,
      ),
    0,
  );

  return {
    eligible: blockers.length === 0,
    title: "Periksa Kondisi Barang",
    stockImpact:
      sellableTotal > 0
        ? `+${amount(sellableTotal)} stok layak jual`
        : "Stok layak jual tidak bertambah",
    note:
      damagedTotal > 0
        ? `${amount(damagedTotal)} barang rusak hanya dicatat sebagai kondisi fisik dan tidak membuat perubahan stok kedua. Barang layak jual masuk ke batch retur baru.`
        : "Barang layak jual akan masuk ke batch retur baru.",
    lines,
    blockers,
  };
}

function lostReview(form: HTMLFormElement): ReviewState {
  const data = formData(form);
  const selected = checked(form, "lostItemId");
  const blockers: string[] = [];

  const lines = selected.map((input) => {
    const id = input.value;
    const quantity = number(
      data.get(`lostQuantity_${id}`),
    );
    const pending = Number(input.dataset.pending ?? "0");

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} memiliki jumlah hilang yang tidak valid.`,
      );
    }

    if (
      Number.isSafeInteger(pending) &&
      quantity > pending
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} melebihi sisa barang yang belum tiba.`,
      );
    }

    return {
      key: id,
      productSku: input.dataset.productSku ?? "Item retur",
      detail: `${amount(quantity)} ditandai hilang`,
      quantity,
    };
  });

  if (!selected.length) {
    blockers.push(
      "Pilih minimal satu item yang memang dinyatakan hilang.",
    );
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Barang Hilang",
    stockImpact: "Stok tidak berubah",
    note:
      "Status hilang hanya dicatat untuk audit dan klaim. Tidak ada perubahan stok tambahan.",
    lines,
    blockers,
  };
}

function lateArrivalReview(
  form: HTMLFormElement,
): ReviewState {
  const data = formData(form);
  const selected = checked(form, "lateReturnLineKey");
  const blockers: string[] = [];
  const totals = new Map<string, number>();

  const lines = selected.map((input) => {
    const key = input.value;
    const quantity = number(
      data.get(`lateQuantity_${key}`),
    );
    const returnItemId = input.dataset.returnItemId ?? "";
    const remainingLost = Number(
      input.dataset.remainingLost ?? "0",
    );

    totals.set(
      returnItemId,
      (totals.get(returnItemId) ?? 0) + quantity,
    );

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} memiliki jumlah kedatangan terlambat yang tidak valid.`,
      );
    }

    if (
      Number.isSafeInteger(remainingLost) &&
      remainingLost > 0 &&
      (totals.get(returnItemId) ?? 0) > remainingLost
    ) {
      blockers.push(
        `${input.dataset.productSku ?? "Item"} melebihi jumlah hilang yang masih dapat dikoreksi.`,
      );
    }

    const verified = input.dataset.verified === "true";
    const batch = input.dataset.batchCode;

    return {
      key,
      productSku: input.dataset.productSku ?? "Item retur",
      detail: verified
        ? `${amount(quantity)} datang dari batch ${batch ?? "-"}`
        : `${amount(quantity)} datang; batch asal belum terverifikasi`,
      quantity,
    };
  });

  if (!selected.length) {
    blockers.push(
      "Pilih minimal satu barang hilang yang ternyata datang.",
    );
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Kedatangan Terlambat",
    stockImpact: "Stok tidak berubah",
    note:
      "Kedatangan terlambat mengurangi jumlah hilang bersih. Jika klaim sudah dikirim atau selesai, sistem akan menandainya untuk ditindaklanjuti.",
    lines,
    blockers,
  };
}

function buildReview(
  kind: ReviewKind,
  form: HTMLFormElement,
) {
  if (kind === "receipt") {
    return receiptReview(form);
  }
  if (kind === "inspection") {
    return inspectionReview(form);
  }
  if (kind === "lost") {
    return lostReview(form);
  }
  return lateArrivalReview(form);
}

function FinalSubmitButton({
  label,
}: {
  label: string;
}) {
  const { pending } = useFormStatus();

  return (
    <Button
      loading={pending}
      loadingLabel="Menyimpan..."
      type="submit"
    >
      {label}
    </Button>
  );
}

export function ReturnMutationReviewForm({
  action,
  children,
  className,
  kind,
  submitLabel,
}: {
  action: (formData: FormData) => void | Promise<void>;
  children: ReactNode;
  className?: string;
  kind: ReviewKind;
  submitLabel: string;
}) {
  const [review, setReview] =
    useState<ReviewState | null>(null);

  function changed(
    event: FormEvent<HTMLFormElement>,
  ) {
    const target = event.target as
      | HTMLInputElement
      | HTMLSelectElement
      | HTMLTextAreaElement;

    if (target.name === "confirmation") {
      return;
    }

    setReview(null);
  }

  function submit(
    event: FormEvent<HTMLFormElement>,
  ) {
    if (review?.eligible) {
      return;
    }

    event.preventDefault();
    setReview(
      buildReview(
        kind,
        event.currentTarget,
      ),
    );
  }

  return (
    <form
      action={action}
      className={className}
      onChange={changed}
      onSubmit={submit}
    >
      {children}

      {review ? (
        <section
          aria-live="polite"
          className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4"
        >
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs font-semibold text-ui-primary">
                Langkah 2 dari 3
              </p>
              <h3 className="mt-1 text-base font-semibold text-ui-text">
                {review.title}
              </h3>
            </div>
            <StatusBadge
              tone={
                review.eligible
                  ? "selected"
                  : "danger"
              }
            >
              {review.eligible
                ? "Siap dikonfirmasi"
                : "Perlu diperbaiki"}
            </StatusBadge>
          </div>

          {review.blockers.length ? (
            <div className="mt-4 space-y-2">
              {review.blockers.map(
                (blocker, index) => (
                  <p
                    className="rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-3 text-sm text-ui-danger"
                    key={`${blocker}-${index}`}
                    role="alert"
                  >
                    {blocker}
                  </p>
                ),
              )}
            </div>
          ) : null}

          {review.lines.length ? (
            <div className="mt-4 divide-y divide-ui-border border-y border-ui-border">
              {review.lines.map((line) => (
                <div
                  className="py-3"
                  key={line.key}
                >
                  <p className="text-sm font-semibold text-ui-text">
                    {line.productSku}
                  </p>
                  <p className="mt-1 text-xs text-ui-text-muted">
                    {line.detail}
                  </p>
                </div>
              ))}
            </div>
          ) : null}

          <div className="mt-4">
            <p className="text-sm font-semibold text-ui-text">
              Dampak setelah disimpan
            </p>
            <p className="mt-1 text-sm font-semibold text-ui-primary">
              {review.stockImpact}
            </p>
            <p className="mt-1 text-sm leading-6 text-ui-text-muted">
              {review.note}
            </p>
          </div>
        </section>
      ) : (
        <div>
          <p className="text-xs font-semibold text-ui-primary">
            Langkah 1 dari 3
          </p>
          <p className="mt-1 text-sm text-ui-text-muted">
            Lengkapi data lalu periksa dampaknya sebelum menyimpan.
          </p>
        </div>
      )}

      {review?.eligible ? (
        <div className="rounded-[var(--ui-radius-md)] border border-ui-border p-4">
          <p className="text-xs font-semibold text-ui-primary">
            Langkah 3 dari 3
          </p>
          <h3 className="mt-1 text-base font-semibold text-ui-text">
            Konfirmasi
          </h3>
          <label className="mt-3 flex items-start gap-3 text-sm text-ui-text">
            <input
              className="mt-1 h-4 w-4"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              Saya sudah memeriksa item, jumlah, dan dampak yang ditampilkan di atas.
            </span>
          </label>
          <div className="mt-4">
            <FinalSubmitButton label={submitLabel} />
          </div>
        </div>
      ) : (
        <Button type="submit">
          Periksa Sebelum Simpan
        </Button>
      )}
    </form>
  );
}