"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import {
  archiveProduct,
  createProduct,
  reactivateProduct,
  updateProduct,
} from "@/lib/supabase-rest";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("PRODUCT_REQUIRED_FIELDS_MISSING");
  }
  return value.trim();
}

function optional(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function productId(formData: FormData) {
  const value = required(formData, "productId");
  if (!UUID_PATTERN.test(value)) throw new Error("PRODUCT_NOT_FOUND");
  return value;
}

function rowVersion(formData: FormData) {
  const value = Number(required(formData, "rowVersion"));
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error("PRODUCT_STALE_VERSION");
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
    throw new Error("PRODUCT_CONFIRMATION_REQUIRED");
  }
}

function productErrorMessage(error: unknown) {
  const raw = error instanceof Error ? error.message : "";
  const messages: Record<string, string> = {
    PRODUCT_REQUIRED_FIELDS_MISSING: "SKU dan nama produk wajib diisi.",
    DUPLICATE_SKU: "SKU tersebut sudah dipakai pada organisasi ini.",
    UNSUPPORTED_UNIT: "Satuan produk harus UNIT.",
    PRODUCT_NOT_FOUND: "Produk tidak ditemukan atau tidak dapat diakses.",
    PRODUCT_STALE_VERSION: "Produk berubah sejak halaman dibuka. Muat ulang lalu periksa kembali.",
    TRANSACTED_SKU_CHANGE_FORBIDDEN: "SKU sudah dipakai transaksi sehingga tidak dapat diubah.",
    PRODUCT_ALREADY_ARCHIVED: "Produk sudah diarsipkan.",
    PRODUCT_NOT_ARCHIVED: "Hanya produk yang diarsipkan yang dapat diaktifkan kembali.",
    PRODUCT_REACTIVATION_CONFLICT: "Produk tidak dapat diaktifkan karena SKU aktif yang sama sudah ada.",
    IDEMPOTENCY_KEY_REUSED: "Referensi aksi sudah digunakan untuk data yang berbeda. Muat ulang formulir.",
    ORGANIZATION_ACCESS_DENIED: "Produk tidak berada pada organisasi Admin aktif.",
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTHENTICATION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    PRODUCT_CONFIRMATION_REQUIRED: "Konfirmasi wajib dicentang sebelum perubahan status.",
  };
  const found = Object.entries(messages).find(([code]) => raw.includes(code));
  return found ? found[1] : "Aksi Produk gagal. Muat ulang halaman dan coba kembali.";
}

function destination(kind: FeedbackKind, message: string, productId?: string) {
  const params = new URLSearchParams({ [kind]: message });
  return productId ? `/products/${productId}?${params.toString()}` : `/products?${params.toString()}#product-form`;
}

function revalidateProducts() {
  revalidatePath("/");
  revalidatePath("/products");
  revalidatePath("/manual-outbounds");
  revalidatePath("/marketplace");
  revalidatePath("/marketplace/listings");
}

export async function createProductAction(formData: FormData) {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  let message: string;
  let createdId: string | undefined;
  try {
    const result = await createProduct({
      organizationId: session.profile.organization_id,
      idempotencyKey: `product-admin:create:${intentId(formData)}`,
      sku: required(formData, "sku"),
      name: required(formData, "name"),
      unitCode: "UNIT",
      description: optional(formData, "description"),
      note: optional(formData, "note"),
    });
    createdId = result.productId;
    message = `${result.sku} berhasil ditambahkan tanpa mengubah stok.`;
    revalidateProducts();
  } catch (error) {
    kind = "error";
    message = productErrorMessage(error);
  }
  redirect(destination(kind, message, createdId));
}

export async function updateProductAction(formData: FormData) {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  const id = typeof formData.get("productId") === "string" ? String(formData.get("productId")) : undefined;
  let message: string;
  try {
    const result = await updateProduct({
      organizationId: session.profile.organization_id,
      idempotencyKey: `product-admin:update:${intentId(formData)}`,
      productId: productId(formData),
      expectedRowVersion: rowVersion(formData),
      sku: required(formData, "sku"),
      name: required(formData, "name"),
      unitCode: "UNIT",
      description: optional(formData, "description"),
      note: optional(formData, "note"),
    });
    message = `${result.sku} disimpan. Snapshot transaksi lama tidak berubah.`;
    revalidateProducts();
  } catch (error) {
    kind = "error";
    message = productErrorMessage(error);
  }
  redirect(destination(kind, message, id));
}

async function productStateAction(formData: FormData, target: "archive" | "reactivate") {
  const session = await requireAdminSession();
  let kind: FeedbackKind = "success";
  const id = typeof formData.get("productId") === "string" ? String(formData.get("productId")) : undefined;
  let message: string;
  try {
    requiresConfirmation(formData);
    const input = {
      organizationId: session.profile.organization_id,
      idempotencyKey: `product-admin:${target}:${intentId(formData)}`,
      productId: productId(formData),
      expectedRowVersion: rowVersion(formData),
      reason: optional(formData, "reason"),
    };
    const result = target === "archive" ? await archiveProduct(input) : await reactivateProduct(input);
    message = target === "archive"
      ? `${result.sku} diarsipkan. Histori dan snapshot stok tetap tersedia.`
      : `${result.sku} kembali aktif untuk transaksi baru.`;
    revalidateProducts();
  } catch (error) {
    kind = "error";
    message = productErrorMessage(error);
  }
  redirect(destination(kind, message, id));
}

export async function archiveProductAction(formData: FormData) {
  return productStateAction(formData, "archive");
}

export async function reactivateProductAction(formData: FormData) {
  return productStateAction(formData, "reactivate");
}