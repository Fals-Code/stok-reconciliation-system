"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import {
  retryNotificationOutboxEvent,
  runNotificationEvaluation,
  type NotificationEvaluationFamilyCode,
} from "@/lib/supabase-rest";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EVALUATION_FAMILIES = [
  "EXPIRY",
  "RETURN_INSPECTION",
  "RECONCILIATION",
  "STOCKTAKE",
] as const satisfies readonly NotificationEvaluationFamilyCode[];

type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function requiredUuid(formData: FormData, key: string, errorCode: string) {
  const value = required(formData, key);

  if (!UUID_PATTERN.test(value)) {
    throw new Error(errorCode);
  }

  return value;
}

function requiredReason(formData: FormData) {
  const reason = required(formData, "reason");

  if (reason.length > 2000) {
    throw new Error("NOTIFICATION_ADMIN_OPERATION_REASON_TOO_LONG");
  }

  return reason;
}

function requiredIdempotencyKey(formData: FormData) {
  const key = required(formData, "idempotencyKey");

  if (key.length > 200) {
    throw new Error(
      "NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_TOO_LONG",
    );
  }

  return key;
}

function requiredEvaluationFamily(
  formData: FormData,
): NotificationEvaluationFamilyCode {
  const family = required(
    formData,
    "evaluationFamilyCode",
  ).toUpperCase();

  if (
    !EVALUATION_FAMILIES.includes(
      family as NotificationEvaluationFamilyCode,
    )
  ) {
    throw new Error("NOTIFICATION_EVALUATION_FAMILY_INVALID");
  }

  return family as NotificationEvaluationFamilyCode;
}

function rawErrorMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Terjadi kesalahan yang tidak diketahui.";
}

function operationErrorMessage(error: unknown) {
  const raw = rawErrorMessage(error);
  const messages: Record<string, string> = {
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    ADMIN_ACCESS_REQUIRED:
      "Akun tidak memiliki akses Admin aktif.",
    NOTIFICATION_ACTOR_NOT_AUTHORIZED:
      "Akun tidak memiliki izin untuk menjalankan operasi ini.",
    NOTIFICATION_EVALUATION_FAMILY_INVALID:
      "Keluarga evaluator tidak valid.",
    NOTIFICATION_EVALUATION_REASON_REQUIRED:
      "Alasan evaluasi wajib diisi.",
    NOTIFICATION_EVALUATION_REASON_TOO_LONG:
      "Alasan evaluasi maksimal 2.000 karakter.",
    NOTIFICATION_ADMIN_OPERATION_REASON_TOO_LONG:
      "Alasan operasi maksimal 2.000 karakter.",
    NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_REQUIRED:
      "Idempotency key operasi wajib tersedia.",
    NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_TOO_LONG:
      "Idempotency key operasi terlalu panjang.",
    NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_CONFLICT:
      "Permintaan dengan idempotency key yang sama memiliki isi berbeda.",
    NOTIFICATION_EVALUATION_ENQUEUE_FAILED:
      "Permintaan evaluator gagal dimasukkan ke outbox.",
    NOTIFICATION_EVALUATION_EVENT_ID_INVALID:
      "Outbox event hasil evaluasi tidak valid.",
    NOTIFICATION_EVALUATION_EVENT_ID_MISSING:
      "Outbox event hasil evaluasi tidak ditemukan.",
    OUTBOX_EVENT_ID_REQUIRED:
      "Outbox event ID wajib diisi.",
    OUTBOX_EVENT_NOT_FOUND:
      "Outbox event tidak ditemukan dalam organisasi aktif.",
    OUTBOX_RETRY_STATUS_INVALID:
      "Hanya event FAILED_RETRYABLE atau FAILED_FINAL yang dapat di-retry.",
    OUTBOX_RETRY_REASON_REQUIRED:
      "Alasan retry wajib diisi.",
    OUTBOX_RETRY_REASON_TOO_LONG:
      "Alasan retry maksimal 2.000 karakter.",
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
) {
  const base = new URL(
    "http://notification.local/notifications/operations",
  );
  const rawReturnTo = String(
    formData.get("returnTo") ??
      "/notifications/operations#overview",
  ).trim();

  let destination: URL;

  try {
    destination = new URL(rawReturnTo, base);
  } catch {
    destination = new URL(
      "/notifications/operations#overview",
      base,
    );
  }

  if (
    destination.origin !== base.origin ||
    destination.pathname !== "/notifications/operations"
  ) {
    destination = new URL(
      "/notifications/operations#overview",
      base,
    );
  }

  destination.searchParams.delete("success");
  destination.searchParams.delete("error");
  destination.searchParams.set(kind, message);

  const query = destination.searchParams.toString();
  const hash = destination.hash || "#overview";

  return `${destination.pathname}${query ? `?${query}` : ""}${hash}`;
}

function refreshOperationsUi() {
  revalidatePath("/notifications/operations");
  revalidatePath("/notifications");
  revalidatePath("/", "layout");
}

export async function runNotificationEvaluationAction(
  formData: FormData,
) {
  await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const family = requiredEvaluationFamily(formData);
    const reason = requiredReason(formData);
    const idempotencyKey = requiredIdempotencyKey(formData);
    const result = await runNotificationEvaluation(
      family,
      reason,
      idempotencyKey,
    );

    message =
      result.action === "REPLAYED"
        ? `Permintaan evaluasi ${family} sudah pernah diterima dan diputar ulang.`
        : `Evaluasi ${family} berhasil dimasukkan ke outbox.`;

    refreshOperationsUi();
  } catch (error) {
    kind = "error";
    message = operationErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message));
}

export async function retryNotificationOutboxEventAction(
  formData: FormData,
) {
  await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const outboxEventId = requiredUuid(
      formData,
      "outboxEventId",
      "OUTBOX_EVENT_ID_REQUIRED",
    );
    const reason = requiredReason(formData);
    const idempotencyKey = requiredIdempotencyKey(formData);
    const result = await retryNotificationOutboxEvent(
      outboxEventId,
      reason,
      idempotencyKey,
    );

    message =
      result.action === "REPLAYED"
        ? "Permintaan retry ini sudah pernah diterima dan diputar ulang."
        : "Outbox event dikembalikan ke antrean retry dengan budget baru.";

    refreshOperationsUi();
  } catch (error) {
    kind = "error";
    message = operationErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message));
}
