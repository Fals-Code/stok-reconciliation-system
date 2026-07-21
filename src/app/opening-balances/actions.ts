"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  openingBalanceTimestamp,
  parseOpeningBalanceLines,
} from "@/app/opening-balances/draft";
import { requireAdminSession } from "@/lib/auth";
import {
  createOpeningBalanceCutover,
  postOpeningBalanceCutover,
  saveOpeningBalanceDraft,
  submitOpeningBalanceReview,
} from "@/lib/supabase-rest";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH_PATTERN = /^[0-9a-f]{64}$/i;

type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key.toUpperCase()}_REQUIRED`);
  }

  return value.trim();
}

function requiredUuid(formData: FormData, key: string) {
  const value = required(formData, key);

  if (!UUID_PATTERN.test(value)) {
    throw new Error("OPENING_BALANCE_CUTOVER_ID_REQUIRED");
  }

  return value;
}

function requiredVersion(formData: FormData) {
  const value = Number(required(formData, "rowVersion"));

  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error("OPENING_BALANCE_VERSION_REQUIRED");
  }

  return value;
}

function requiredPreviewHash(formData: FormData) {
  const value = required(formData, "previewBasisHash").toLowerCase();

  if (!HASH_PATTERN.test(value)) {
    throw new Error("OPENING_BALANCE_PREVIEW_HASH_INVALID");
  }

  return value;
}

function requiredConfirmation(formData: FormData) {
  if (formData.get("confirmation") !== "on") {
    throw new Error("OPENING_BALANCE_CONFIRMATION_REQUIRED");
  }

  return true;
}

function errorMessage(error: unknown) {
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
      "Dokumen saldo awal tidak berada dalam organisasi aktif.",
    OPENING_BALANCE_SOURCE_REQUIRED:
      "Referensi dokumen sumber wajib diisi.",
    OPENING_BALANCE_SOURCE_TOO_LONG:
      "Referensi dokumen sumber maksimal 200 karakter.",
    OPENING_BALANCE_ESTIMATE_REFERENCE_REQUIRED:
      "Referensi estimasi atau bukti sumber wajib diisi.",
    OPENING_BALANCE_ESTIMATE_REFERENCE_TOO_LONG:
      "Referensi estimasi maksimal 200 karakter.",
    OPENING_BALANCE_NOTE_REQUIRED:
      "Catatan dasar saldo awal wajib diisi.",
    OPENING_BALANCE_NOTE_TOO_LONG:
      "Catatan maksimal 2.000 karakter.",
    OPENING_BALANCE_CUTOVER_AT_REQUIRED:
      "Tanggal dan waktu cutover wajib diisi.",
    OPENING_BALANCE_CUTOVER_NOT_FOUND:
      "Dokumen saldo awal tidak ditemukan.",
    OPENING_BALANCE_DRAFT_NOT_EDITABLE:
      "Dokumen sudah masuk review dan tidak dapat diedit sebagai draft.",
    OPENING_BALANCE_CUTOVER_NOT_DRAFT:
      "Hanya draft yang dapat dikirim ke review.",
    OPENING_BALANCE_VERSION_REQUIRED:
      "Versi draft tidak valid. Muat ulang halaman.",
    STALE_OPENING_BALANCE_DRAFT:
      "Draft berubah di proses lain. Muat ulang sebelum menyimpan.",
    OPENING_BALANCE_LINES_REQUIRED:
      "Tambahkan minimal satu baris saldo awal.",
    OPENING_BALANCE_LINES_LIMIT_EXCEEDED:
      "Satu dokumen maksimal memuat 500 baris.",
    OPENING_BALANCE_LINE_INVALID:
      "Terdapat baris saldo awal yang belum lengkap atau tidak valid.",
    OPENING_BALANCE_DUPLICATE_BATCH_BUCKET_LINE:
      "Produk, batch, dan bucket yang sama tidak boleh dicatat dua kali.",
    OPENING_BALANCE_DUPLICATE_SOURCE_LINE:
      "Referensi baris sumber tidak boleh duplikat.",
    UNKNOWN_BATCH_NOT_QUARANTINED:
      "Batch yang belum terverifikasi hanya boleh masuk bucket quarantine dengan referensi pengecualian.",
    OPENING_BALANCE_VERIFIED_BATCH_EXCEPTION_FORBIDDEN:
      "Baris batch terverifikasi tidak boleh memakai referensi pengecualian.",
    OPENING_BALANCE_EXCEPTION_REFERENCE_TOO_LONG:
      "Referensi pengecualian maksimal 200 karakter.",
    OPENING_BALANCE_PREVIEW_HASH_INVALID:
      "Basis preview tidak valid. Tinjau ulang dokumen.",
    STALE_OPENING_BALANCE_PREVIEW:
      "Ledger atau projection berubah setelah preview. Tinjau ulang sebelum posting.",
    OPENING_BALANCE_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang.",
    OPENING_BALANCE_ACTIVE_CUTOVER_EXISTS:
      "Masih ada cutover saldo awal aktif. Balikkan cutover lama melalui jalur koreksi sebelum membuat pengganti.",
    OPENING_BALANCE_BATCH_PROJECTION_DRIFT:
      "Projection batch berbeda dari ledger. Jalankan investigasi rekonsiliasi.",
    OPENING_BALANCE_PRODUCT_PROJECTION_DRIFT:
      "Projection produk berbeda dari ledger. Jalankan investigasi rekonsiliasi.",
    OPENING_BALANCE_SELLABLE_BATCH_NOT_ACTIVE:
      "Saldo sellable hanya dapat masuk ke batch aktif.",
    OPENING_BALANCE_SELLABLE_BATCH_EXPIRED:
      "Batch kedaluwarsa tidak dapat menerima saldo sellable.",
    OPENING_BALANCE_UNIDENTIFIED_BATCH_SCOPE_INVALID:
      "Batch tanpa identitas hanya dapat dicatat sebagai quarantine exception.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi posting sudah digunakan untuk payload berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Posting yang sama masih diproses.",
    IDEMPOTENCY_COMMAND_FAILED:
      "Percobaan posting sebelumnya gagal dan tidak dapat dipakai ulang.",
  };

  const match = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return match ? match[1] : raw;
}

function destination(
  kind: FeedbackKind,
  message: string,
  cutoverId?: string,
  transactionId?: string,
  anchor = "detail",
) {
  const params = new URLSearchParams({ [kind]: message });

  if (cutoverId) params.set("cutoverId", cutoverId);
  if (transactionId) params.set("transactionId", transactionId);

  return `/opening-balances?${params.toString()}#${anchor}`;
}

function revalidateOpeningBalance() {
  revalidatePath("/opening-balances");
  revalidatePath("/");
  revalidatePath("/reconciliation");
}

export async function createOpeningBalanceAction(formData: FormData) {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  let message: string;
  let cutoverId: string | undefined;

  try {
    const result = await createOpeningBalanceCutover({
      organizationId: session.profile.organization_id,
      sourceRef: required(formData, "sourceRef"),
      cutoverAt: openingBalanceTimestamp(
        required(formData, "cutoverAt"),
      ),
      sourceEstimateRef: required(formData, "sourceEstimateRef"),
      note: required(formData, "note"),
      metadata: {
        source: "opening-balance-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    cutoverId = result.cutoverId;
    message = `${result.cutoverNo} dibuat sebagai draft. Tambahkan baris stok sebelum review.`;
    revalidateOpeningBalance();
  } catch (error) {
    kind = "error";
    message = errorMessage(error);
  }

  redirect(destination(kind, message, cutoverId, undefined, "detail"));
}

export async function saveOpeningBalanceDraftAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const cutoverId = requiredUuid(formData, "cutoverId");
  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const lines = parseOpeningBalanceLines(
      required(formData, "linesJson"),
    );
    const result = await saveOpeningBalanceDraft({
      organizationId: session.profile.organization_id,
      cutoverId,
      expectedRowVersion: requiredVersion(formData),
      cutoverAt: openingBalanceTimestamp(
        required(formData, "cutoverAt"),
      ),
      sourceEstimateRef: required(formData, "sourceEstimateRef"),
      note: required(formData, "note"),
      lines,
      metadata: {
        source: "opening-balance-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message =
      `Draft tersimpan: ${result.lineCount} baris, ` +
      `${result.positiveLineCount} baris positif, ` +
      `${result.totalQuantity} unit.`;
    revalidateOpeningBalance();
  } catch (error) {
    kind = "error";
    message = errorMessage(error);
  }

  redirect(destination(kind, message, cutoverId, undefined, "draft"));
}

export async function submitOpeningBalanceReviewAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const cutoverId = requiredUuid(formData, "cutoverId");
  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const result = await submitOpeningBalanceReview({
      organizationId: session.profile.organization_id,
      cutoverId,
      expectedRowVersion: requiredVersion(formData),
    });

    message =
      `${result.lineCount} baris dikunci untuk review. ` +
      "Preview authoritative sudah dihitung ulang.";
    revalidateOpeningBalance();
  } catch (error) {
    kind = "error";
    message = errorMessage(error);
  }

  redirect(destination(kind, message, cutoverId, undefined, "preview"));
}

export async function postOpeningBalanceAction(formData: FormData) {
  const session = await requireAdminSession();
  const cutoverId = requiredUuid(formData, "cutoverId");
  let kind: FeedbackKind = "success";
  let message: string;
  let transactionId: string | undefined;

  try {
    const intentId = required(formData, "intentId");
    const result = await postOpeningBalanceCutover({
      organizationId: session.profile.organization_id,
      cutoverId,
      idempotencyKey: `opening-balance:${cutoverId}:post:${intentId}`,
      previewBasisHash: requiredPreviewHash(formData),
      confirmation: requiredConfirmation(formData),
    });

    transactionId = result.transactionId;
    message =
      `${result.cutoverNo} berhasil diposting: ` +
      `${result.positiveLineCount} movement, ${result.totalQuantity} unit. ` +
      "Status awal tetap belum terverifikasi sampai stok opname pertama.";
    revalidateOpeningBalance();
  } catch (error) {
    kind = "error";
    message = errorMessage(error);
  }

  redirect(
    destination(kind, message, cutoverId, transactionId, "detail"),
  );
}
