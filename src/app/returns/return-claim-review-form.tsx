"use client";

import {
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { useFormStatus } from "react-dom";

import { Button, StatusBadge } from "@/components/ui";

type ClaimReviewKind =
  | "create"
  | "submit"
  | "resolve"
  | "cancel";

type ClaimReviewState = {
  eligible: boolean;
  title: string;
  summary: string;
  consequence: string;
  details: string[];
  blockers: string[];
};

const resolutionLabels: Record<string, string> = {
  APPROVED: "Disetujui",
  PARTIALLY_APPROVED: "Disetujui sebagian",
  REJECTED: "Ditolak",
  NO_ACTION: "Tidak ada tindakan",
  OTHER: "Lainnya",
};

function amount(value: number) {
  return new Intl.NumberFormat("id-ID").format(value);
}

function numeric(value: FormDataEntryValue | null) {
  const parsed = Number(String(value ?? "0"));
  return Number.isSafeInteger(parsed) ? parsed : Number.NaN;
}

function selectedCheckboxes(
  form: HTMLFormElement,
  name: string,
) {
  return Array.from(
    form.querySelectorAll<HTMLInputElement>(
      `input[type="checkbox"][name="${name}"]:checked`,
    ),
  );
}

function createReview(
  form: HTMLFormElement,
): ClaimReviewState {
  const data = new FormData(form);
  const selected = selectedCheckboxes(form, "claimItemId");
  const blockers: string[] = [];
  const details: string[] = [];
  let total = 0;

  for (const input of selected) {
    const id = input.value;
    const quantity = numeric(data.get(`quantity_${id}`));
    const maximum = Number(input.dataset.maximum ?? "0");
    const sku = input.dataset.productSku ?? "Item retur";

    if (!Number.isSafeInteger(quantity) || quantity <= 0) {
      blockers.push(`${sku} memiliki jumlah klaim yang tidak valid.`);
      continue;
    }

    if (
      Number.isSafeInteger(maximum) &&
      maximum > 0 &&
      quantity > maximum
    ) {
      blockers.push(
        `${sku} melebihi jumlah yang masih dapat diklaim.`,
      );
    }

    total += quantity;
    details.push(`${sku}: ${amount(quantity)} unit`);
  }

  if (!selected.length) {
    blockers.push(
      "Pilih minimal satu barang hilang yang akan diklaim.",
    );
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Klaim Baru",
    summary: `${amount(total)} unit akan dimasukkan ke klaim`,
    consequence: "Klaim tidak mengubah stok",
    details,
    blockers,
  };
}

function submitReview(
  form: HTMLFormElement,
): ClaimReviewState {
  const data = new FormData(form);
  const externalRef = String(
    data.get("externalClaimRef") ?? "",
  ).trim();
  const deadline = String(
    form.dataset.deadlineLabel ?? "",
  ).trim();
  const blockers: string[] = [];

  if (!externalRef) {
    blockers.push("Referensi klaim TikTok wajib diisi.");
  }

  if (externalRef.length > 200) {
    blockers.push(
      "Referensi klaim TikTok maksimal 200 karakter.",
    );
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Pengiriman Klaim",
    summary: externalRef
      ? `Referensi TikTok: ${externalRef}`
      : "Referensi TikTok belum diisi",
    consequence: "Status klaim akan menjadi Sudah dikirim",
    details: deadline ? [`Batas klaim: ${deadline}`] : [],
    blockers,
  };
}

function resolveReview(
  form: HTMLFormElement,
): ClaimReviewState {
  const data = new FormData(form);
  const resolution = String(
    data.get("resolutionCode") ?? "",
  ).trim();
  const blockers: string[] = [];

  if (!resolutionLabels[resolution]) {
    blockers.push("Pilih hasil klaim yang valid.");
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Penyelesaian Klaim",
    summary: resolution
      ? `Hasil: ${resolutionLabels[resolution] ?? resolution}`
      : "Hasil klaim belum dipilih",
    consequence: "Status klaim akan menjadi Selesai",
    details: [
      "Penyelesaian klaim tidak mengubah stok.",
    ],
    blockers,
  };
}

function cancelReview(
  form: HTMLFormElement,
): ClaimReviewState {
  const data = new FormData(form);
  const reason = String(data.get("reason") ?? "").trim();
  const blockers: string[] = [];

  if (!reason) {
    blockers.push("Alasan pembatalan klaim wajib diisi.");
  }

  return {
    eligible: blockers.length === 0,
    title: "Periksa Pembatalan Klaim",
    summary: reason
      ? `Alasan: ${reason}`
      : "Alasan belum diisi",
    consequence: "Klaim akan ditutup sebagai Dibatalkan",
    details: [
      "Pembatalan klaim tidak mengubah stok.",
      "Quantity pada klaim yang dibatalkan tidak lagi mengurangi kapasitas klaim aktif.",
    ],
    blockers,
  };
}

function buildReview(
  kind: ClaimReviewKind,
  form: HTMLFormElement,
) {
  if (kind === "create") {
    return createReview(form);
  }
  if (kind === "submit") {
    return submitReview(form);
  }
  if (kind === "resolve") {
    return resolveReview(form);
  }
  return cancelReview(form);
}

function CommitButton({
  label,
  variant,
}: {
  label: string;
  variant: "primary" | "secondary" | "danger";
}) {
  const { pending } = useFormStatus();

  return (
    <Button
      loading={pending}
      loadingLabel="Menyimpan..."
      type="submit"
      variant={variant}
    >
      {label}
    </Button>
  );
}

export function ReturnClaimReviewForm({
  action,
  children,
  className,
  deadlineLabel,
  kind,
  submitLabel,
  submitVariant = "primary",
}: {
  action: (formData: FormData) => void | Promise<void>;
  children: ReactNode;
  className?: string;
  deadlineLabel?: string;
  kind: ClaimReviewKind;
  submitLabel: string;
  submitVariant?: "primary" | "secondary" | "danger";
}) {
  const [review, setReview] =
    useState<ClaimReviewState | null>(null);

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
    setReview(buildReview(kind, event.currentTarget));
  }

  return (
    <form
      action={action}
      className={className}
      data-deadline-label={deadlineLabel}
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
              tone={review.eligible ? "selected" : "danger"}
            >
              {review.eligible
                ? "Siap dikonfirmasi"
                : "Perlu diperbaiki"}
            </StatusBadge>
          </div>

          {review.blockers.length ? (
            <div className="mt-4 space-y-2">
              {review.blockers.map((blocker, index) => (
                <p
                  className="rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-3 text-sm text-ui-danger"
                  key={`${blocker}-${index}`}
                  role="alert"
                >
                  {blocker}
                </p>
              ))}
            </div>
          ) : null}

          <div className="mt-4">
            <p className="text-sm font-semibold text-ui-text">
              {review.summary}
            </p>
            <p className="mt-2 text-sm font-semibold text-ui-primary">
              {review.consequence}
            </p>
          </div>

          {review.details.length ? (
            <div className="mt-3 space-y-1">
              {review.details.map((detail) => (
                <p
                  className="text-sm text-ui-text-muted"
                  key={detail}
                >
                  {detail}
                </p>
              ))}
            </div>
          ) : null}
        </section>
      ) : (
        <div>
          <p className="text-xs font-semibold text-ui-primary">
            Langkah 1 dari 3
          </p>
          <p className="mt-1 text-sm text-ui-text-muted">
            Lengkapi data klaim lalu periksa sebelum menyimpan.
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
              Saya sudah memeriksa data dan konsekuensi klaim di atas.
            </span>
          </label>
          <div className="mt-4">
            <CommitButton
              label={submitLabel}
              variant={submitVariant}
            />
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