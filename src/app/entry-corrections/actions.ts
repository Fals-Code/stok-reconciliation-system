"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import { reverseStockTransaction } from "@/lib/supabase-rest";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;

type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function requiredUuid(formData: FormData, key: string) {
  const value = required(formData, key);

  if (!UUID_PATTERN.test(value)) {
    throw new Error("ORIGINAL_TRANSACTION_ID_REQUIRED");
  }

  return value;
}

function requiredPreviewHash(formData: FormData) {
  const value = required(formData, "previewBasisHash").toLowerCase();

  if (!SHA256_PATTERN.test(value)) {
    throw new Error("REVERSAL_PREVIEW_HASH_INVALID");
  }

  return value;
}

function requiredNote(formData: FormData) {
  const value = formData.get("note");

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("REVERSAL_NOTE_REQUIRED");
  }

  const note = value.trim();

  if (note.length > 2000) {
    throw new Error("REVERSAL_NOTE_TOO_LONG");
  }

  return note;
}

function requiredConfirmation(formData: FormData) {
  if (formData.get("confirmation") !== "on") {
    throw new Error("REVERSAL_CONFIRMATION_REQUIRED");
  }

  return true;
}

function reversalErrorMessage(error: unknown) {
  const raw =
    error instanceof Error
      ? error.message
      : "Terjadi kesalahan yang tidak diketahui.";

  const messages: Record<string, string> = {
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    ORGANIZATION_ACCESS_DENIED:
      "Transaksi tidak berada dalam organisasi aktif.",
    ORIGINAL_TRANSACTION_ID_REQUIRED:
      "Transaction ID tidak valid.",
    ORIGINAL_TRANSACTION_NOT_FOUND:
      "Transaksi asal tidak ditemukan.",
    REVERSAL_TRANSACTION_TYPE_NOT_SUPPORTED:
      "Jenis transaksi ini tidak dapat dikoreksi melalui Koreksi Entri generik.",
    REVERSAL_ORIGINAL_ENTRIES_REQUIRED:
      "Transaksi asal tidak memiliki ledger entry yang dapat dibalik.",
    ORIGINAL_TRANSACTION_ALREADY_REVERSED:
      "Transaksi tersebut sudah pernah dibalik.",
    REVERSAL_NEGATIVE_BUCKET:
      "Koreksi ditolak karena akan membuat saldo batch menjadi negatif.",
    REVERSAL_RESERVED_CONFLICT:
      "Koreksi ditolak karena reserved stock akan melebihi sellable stock.",
    REVERSAL_PROJECTION_DRIFT:
      "Projection stok tidak sama dengan ledger. Jalankan investigasi rekonsiliasi sebelum koreksi.",
    STALE_REVERSAL_PREVIEW:
      "Posisi stok berubah setelah preview dibuat. Tinjau preview terbaru sebelum mengonfirmasi ulang.",
    REVERSAL_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang.",
    REVERSAL_NOTE_REQUIRED:
      "Alasan koreksi wajib diisi.",
    REVERSAL_NOTE_TOO_LONG:
      "Alasan koreksi maksimal 2.000 karakter.",
    REVERSAL_PREVIEW_HASH_INVALID:
      "Basis preview tidak valid. Muat ulang detail transaksi.",
    IDEMPOTENCY_KEY_REQUIRED:
      "Referensi koreksi tidak tersedia. Muat ulang halaman.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi koreksi sudah digunakan untuk permintaan berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Koreksi yang sama masih diproses.",
    IDEMPOTENCY_COMMAND_FAILED:
      "Percobaan koreksi sebelumnya gagal dan tidak dapat dipakai ulang.",
    REVERSAL_NOT_ALLOWED:
      "Transaksi tidak memenuhi syarat untuk dikoreksi.",
  };

  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}

function actionDestination(
  formData: FormData,
  kind: FeedbackKind,
  message: string,
  result?: {
    originalTransactionId: string;
    reversalTransactionId: string;
  },
) {
  const base = new URL("http://entry-correction.local/entry-corrections");
  const rawReturnTo = String(
    formData.get("returnTo") ?? "/entry-corrections",
  ).trim();

  let destination: URL;

  try {
    destination = new URL(rawReturnTo, base);
  } catch {
    destination = new URL("/entry-corrections", base);
  }

  if (
    destination.origin !== base.origin ||
    destination.pathname !== "/entry-corrections"
  ) {
    destination = new URL("/entry-corrections", base);
  }

  destination.searchParams.delete("success");
  destination.searchParams.delete("error");
  destination.searchParams.delete("originalId");
  destination.searchParams.delete("reversalId");
  destination.searchParams.set(kind, message);

  if (result) {
    destination.searchParams.set(
      "transactionId",
      result.originalTransactionId,
    );
    destination.searchParams.set(
      "originalId",
      result.originalTransactionId,
    );
    destination.searchParams.set(
      "reversalId",
      result.reversalTransactionId,
    );
  }

  const query = destination.searchParams.toString();
  const hash = destination.hash || "#detail";

  return `${destination.pathname}${query ? `?${query}` : ""}${hash}`;
}

export async function reverseStockTransactionAction(formData: FormData) {
  const session = await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;
  let resultIds:
    | {
        originalTransactionId: string;
        reversalTransactionId: string;
      }
    | undefined;

  try {
    const originalTransactionId = requiredUuid(
      formData,
      "originalTransactionId",
    );
    const previewBasisHash = requiredPreviewHash(formData);
    const idempotencyKey = required(formData, "idempotencyKey");

    if (idempotencyKey.length > 200) {
      throw new Error("IDEMPOTENCY_KEY_TOO_LONG");
    }

    const note = requiredNote(formData);
    const confirmation = requiredConfirmation(formData);

    const result = await reverseStockTransaction({
      organizationId: session.profile.organization_id,
      originalTransactionId,
      previewBasisHash,
      idempotencyKey,
      confirmation,
      note,
      metadata: {
        source: "entry-corrections-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = `${result.reversalTransactionNo} berhasil membalik ${result.originalTransactionNo} secara penuh.`;
    resultIds = {
      originalTransactionId: result.originalTransactionId,
      reversalTransactionId: result.reversalTransactionId,
    };

    revalidatePath("/entry-corrections");
    revalidatePath("/");
    revalidatePath("/reconciliation");
  } catch (error) {
    kind = "error";
    message = reversalErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message, resultIds));
}
