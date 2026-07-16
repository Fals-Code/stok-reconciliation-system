"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import {
  acknowledgeNotification,
  revokeNotificationAcknowledgment,
  setNotificationReadState,
  type NotificationReadStateCode,
} from "@/lib/supabase-rest";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const READ_STATES = [
  "UNREAD",
  "READ",
  "ARCHIVED_FOR_USER",
] as const satisfies readonly NotificationReadStateCode[];

type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function requiredNotificationId(formData: FormData) {
  const notificationId = required(formData, "notificationId");

  if (!UUID_PATTERN.test(notificationId)) {
    throw new Error("NOTIFICATION_ID_REQUIRED");
  }

  return notificationId;
}

function optionalNote(formData: FormData) {
  const value = formData.get("note");

  if (typeof value !== "string") {
    return null;
  }

  const note = value.trim();

  if (!note) {
    return null;
  }

  if (note.length > 2000) {
    throw new Error("NOTIFICATION_ACKNOWLEDGMENT_NOTE_TOO_LONG");
  }

  return note;
}

function requiredReadState(formData: FormData): NotificationReadStateCode {
  const readState = required(formData, "readStateCode").toUpperCase();

  if (!READ_STATES.includes(readState as NotificationReadStateCode)) {
    throw new Error("NOTIFICATION_READ_STATE_INVALID");
  }

  return readState as NotificationReadStateCode;
}

function rawErrorMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Terjadi kesalahan yang tidak diketahui.";
}

function notificationErrorMessage(error: unknown) {
  const raw = rawErrorMessage(error);
  const messages: Record<string, string> = {
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    ADMIN_ACCESS_REQUIRED:
      "Akun tidak memiliki akses Admin aktif.",
    NOTIFICATION_ACTOR_NOT_AUTHORIZED:
      "Akun tidak memiliki akses untuk mengubah notifikasi ini.",
    NOTIFICATION_ID_REQUIRED:
      "Notification ID tidak valid.",
    NOTIFICATION_NOT_FOUND:
      "Notifikasi tidak ditemukan dalam organisasi aktif.",
    NOTIFICATION_ALREADY_RESOLVED:
      "Notifikasi yang sudah resolved tidak dapat diubah lifecycle-nya.",
    NOTIFICATION_ACKNOWLEDGMENT_NOTE_TOO_LONG:
      "Catatan acknowledgment maksimal 2.000 karakter.",
    NOTIFICATION_ACKNOWLEDGED_AT_STALE:
      "Waktu acknowledgment lebih lama daripada awal notification episode.",
    NOTIFICATION_REVOCATION_TIME_STALE:
      "Waktu pembatalan acknowledgment tidak valid.",
    NOTIFICATION_STATE_CHANGED_AT_STALE:
      "Waktu perubahan status baca tidak valid.",
    NOTIFICATION_READ_STATE_INVALID:
      "Status baca notification tidak valid.",
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
  const base = new URL("http://notification.local/notifications");
  const rawReturnTo = String(
    formData.get("returnTo") ?? "/notifications#detail",
  ).trim();

  let destination: URL;

  try {
    destination = new URL(rawReturnTo, base);
  } catch {
    destination = new URL("/notifications#detail", base);
  }

  if (
    destination.origin !== base.origin ||
    destination.pathname !== "/notifications"
  ) {
    destination = new URL("/notifications#detail", base);
  }

  destination.searchParams.delete("success");
  destination.searchParams.delete("error");
  destination.searchParams.set(kind, message);

  const query = destination.searchParams.toString();
  const hash = destination.hash || "#detail";

  return `${destination.pathname}${query ? `?${query}` : ""}${hash}`;
}

function refreshNotificationUi() {
  revalidatePath("/notifications");
  revalidatePath("/", "layout");
}

function readStateSuccessMessage(
  readState: NotificationReadStateCode,
  action: string,
) {
  if (action === "ALREADY_UNREAD") {
    return "Notifikasi sudah berstatus belum dibaca.";
  }

  if (action === "ALREADY_READ") {
    return "Notifikasi sudah berstatus dibaca.";
  }

  if (action === "ALREADY_ARCHIVED") {
    return "Notifikasi sudah berada di arsip pribadi.";
  }

  if (readState === "UNREAD") {
    return "Notifikasi ditandai belum dibaca.";
  }

  if (readState === "READ") {
    return "Notifikasi ditandai sudah dibaca.";
  }

  return "Notifikasi dipindahkan ke arsip pribadi.";
}

export async function setNotificationReadStateAction(formData: FormData) {
  await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const notificationId = requiredNotificationId(formData);
    const readState = requiredReadState(formData);
    const result = await setNotificationReadState(
      notificationId,
      readState,
    );

    message = readStateSuccessMessage(readState, result.action);
    refreshNotificationUi();
  } catch (error) {
    kind = "error";
    message = notificationErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message));
}

export async function acknowledgeNotificationAction(formData: FormData) {
  await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const notificationId = requiredNotificationId(formData);
    const note = optionalNote(formData);
    const result = await acknowledgeNotification(notificationId, note);

    message =
      result.action === "ALREADY_ACKNOWLEDGED"
        ? "Notifikasi sudah acknowledged."
        : "Notifikasi berhasil di-acknowledge.";

    refreshNotificationUi();
  } catch (error) {
    kind = "error";
    message = notificationErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message));
}

export async function revokeNotificationAcknowledgmentAction(
  formData: FormData,
) {
  await requireAdminSession();

  let kind: FeedbackKind = "success";
  let message: string;

  try {
    const notificationId = requiredNotificationId(formData);
    const note = optionalNote(formData);
    const result = await revokeNotificationAcknowledgment(
      notificationId,
      note,
    );

    message =
      result.action === "ALREADY_OPEN"
        ? "Notifikasi sudah berada pada lifecycle open."
        : "Acknowledgment berhasil dibatalkan dan notification kembali open.";

    refreshNotificationUi();
  } catch (error) {
    kind = "error";
    message = notificationErrorMessage(error);
  }

  redirect(actionDestination(formData, kind, message));
}
