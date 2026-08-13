"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import {
  createPromoReference,
  updatePromoReference,
  archivePromoReference,
  reactivatePromoReference,
} from "@/lib/supabase-rest";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("PROMO_REFERENCE_REQUIRED_FIELDS_MISSING");
  }
  return value.trim();
}

function optional(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function promoId(formData: FormData) {
  const value = required(formData, "promoId");
  if (!UUID_PATTERN.test(value)) throw new Error("PROMO_REFERENCE_NOT_FOUND");
  return value;
}

function rowVersion(formData: FormData) {
  const value = Number(required(formData, "rowVersion"));
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error("CONCURRENCY_ERROR");
  }
  return value;
}

function intentId(formData: FormData) {
  const value = required(formData, "intentId");
  if (!UUID_PATTERN.test(value)) throw new Error("IDEMPOTENCY_KEY_REUSED");
  return value;
}

function requiresConfirmation(formData: FormData) {
  if (formData.get("confirmation") !== "on") {
    throw new Error("PROMO_CONFIRMATION_REQUIRED");
  }
}

function promoErrorMessage(error: unknown) {
  const raw = error instanceof Error ? error.message : "";
  const messages: Record<string, string> = {
    PROMO_REFERENCE_REQUIRED_FIELDS_MISSING: "Kode promo dan nama wajib diisi.",
    DUPLICATE_PROMO_CODE: "Referensi promo dengan kode yang sama sudah terdaftar.",
    PROMO_REFERENCE_NOT_FOUND: "Referensi promo tidak ditemukan atau tidak dapat diakses.",
    CONCURRENCY_ERROR: "Referensi promo berubah sejak halaman dibuka. Muat ulang halaman lalu periksa kembali.",
    PROMO_REFERENCE_ALREADY_INACTIVE: "Referensi promo sudah dalam keadaan tidak aktif.",
    PROMO_REFERENCE_ALREADY_ACTIVE: "Referensi promo sudah dalam keadaan aktif.",
    PROMO_REFERENCE_DELETE_FORBIDDEN: "Penghapusan fisik referensi promo tidak diizinkan oleh sistem.",
    IDEMPOTENCY_KEY_REUSED: "Referensi aksi sudah digunakan untuk data yang berbeda. Muat ulang formulir.",
    ORGANIZATION_ACCESS_DENIED: "Referensi promo tidak berada pada organisasi Admin aktif.",
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTHENTICATION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    PROMO_CONFIRMATION_REQUIRED: "Konfirmasi wajib dicentang sebelum melakukan perubahan status.",
  };
  const found = Object.entries(messages).find(([code]) => raw.includes(code));
  return found ? found[1] : "Aksi Promo gagal. Muat ulang halaman dan coba kembali.";
}

function destination(kind: FeedbackKind, message: string) {
  const params = new URLSearchParams({ [kind]: message });
  return `/settings/promos?${params.toString()}`;
}

function revalidatePromos() {
  revalidatePath("/settings/promos");
  revalidatePath("/manual-outbounds");
}

export async function createPromoReferenceAction(formData: FormData) {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  let message: string;
  try {
    const codeVal = required(formData, "code");
    const nameVal = required(formData, "name");
    const descVal = optional(formData, "description");

    const result = await createPromoReference({
      organizationId: session.profile.organization_id,
      idempotencyKey: `promo-admin:create:${intentId(formData)}`,
      code: codeVal,
      name: nameVal,
      description: descVal,
    });
    message = `Referensi Promo "${result.code}" berhasil ditambahkan.`;
    revalidatePromos();
  } catch (error) {
    kind = "error";
    message = promoErrorMessage(error);
  }
  redirect(destination(kind, message));
}

export async function updatePromoReferenceAction(formData: FormData) {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  let message: string;
  try {
    const idVal = promoId(formData);
    const versionVal = rowVersion(formData);
    const nameVal = required(formData, "name");
    const descVal = optional(formData, "description");

    const result = await updatePromoReference({
      organizationId: session.profile.organization_id,
      idempotencyKey: `promo-admin:update:${intentId(formData)}`,
      id: idVal,
      expectedRowVersion: versionVal,
      name: nameVal,
      description: descVal,
    });
    message = `Referensi Promo "${result.code}" berhasil diperbarui.`;
    revalidatePromos();
  } catch (error) {
    kind = "error";
    message = promoErrorMessage(error);
  }
  redirect(destination(kind, message));
}

async function promoLifecycleAction(formData: FormData, target: "archive" | "reactivate") {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  let message: string;
  try {
    requiresConfirmation(formData);
    const idVal = promoId(formData);
    const versionVal = rowVersion(formData);
    const reasonVal = optional(formData, "reason");

    const input = {
      organizationId: session.profile.organization_id,
      idempotencyKey: `promo-admin:${target}:${intentId(formData)}`,
      id: idVal,
      expectedRowVersion: versionVal,
      reason: reasonVal,
    };

    const result = target === "archive"
      ? await archivePromoReference(input)
      : await reactivatePromoReference(input);

    message = target === "archive"
      ? `Referensi Promo "${result.code}" berhasil dinonaktifkan. Transaksi yang sudah tercatat tidak berubah.`
      : `Referensi Promo "${result.code}" berhasil diaktifkan kembali untuk transaksi baru.`;
    revalidatePromos();
  } catch (error) {
    kind = "error";
    message = promoErrorMessage(error);
  }
  redirect(destination(kind, message));
}

export async function archivePromoReferenceAction(formData: FormData) {
  return promoLifecycleAction(formData, "archive");
}

export async function reactivatePromoReferenceAction(formData: FormData) {
  return promoLifecycleAction(formData, "reactivate");
}
