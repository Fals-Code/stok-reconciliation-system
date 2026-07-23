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
function batchErrorMessage(error:unknown){const raw=error instanceof Error?error.message:"";const map:Record<string,string>={BATCH_REQUIRED_FIELDS_MISSING:"Kode batch dan tanggal kedaluwarsa wajib diisi.",DUPLICATE_PRODUCT_BATCH:"Kode batch sudah dipakai untuk Produk ini.",EXPIRY_DATE_REQUIRED:"Tanggal kedaluwarsa wajib diisi.",INVALID_BATCH_DATE_RANGE:"Tanggal produksi tidak boleh setelah kedaluwarsa.",MANUAL_BATCH_KIND_FORBIDDEN:"Admin hanya dapat membuat Batch STANDARD.",PRODUCT_NOT_FOUND:"Produk tidak ditemukan.",INACTIVE_PRODUCT_FOR_TRANSACTION:"Produk diarsipkan dan tidak dapat menerima Batch baru.",BATCH_NOT_FOUND:"Batch tidak ditemukan.",BATCH_STALE_VERSION:"Batch berubah sejak halaman dibuka. Muat ulang.",BATCH_PRODUCT_CHANGE_FORBIDDEN:"Produk Batch tidak dapat dipindahkan.",BATCH_KIND_CHANGE_FORBIDDEN:"Jenis Batch tidak dapat diubah.",BATCH_STATUS_REASON_REQUIRED:"Alasan status Batch wajib diisi.",EXPIRY_CHANGE_REASON_REQUIRED:"Koreksi kedaluwarsa setelah ada histori wajib diberi alasan.",BATCH_EFFECTIVELY_EXPIRED:"Batch efektif kedaluwarsa tidak dapat diaktifkan.",BATCH_ALREADY_BLOCKED:"Batch sudah diblokir.",BATCH_NOT_BLOCKED:"Hanya Batch BLOCKED yang dapat dibuka.",BATCH_ALREADY_ARCHIVED:"Batch sudah diarsipkan.",BATCH_NOT_ARCHIVED:"Hanya Batch ARCHIVED yang dapat diaktifkan kembali.",BATCH_REACTIVATION_CONFLICT:"Reaktivasi Batch berbenturan dengan identitas Batch lain.",IDEMPOTENCY_KEY_REUSED:"Referensi aksi sudah dipakai untuk data berbeda.",ORGANIZATION_ACCESS_DENIED:"Batch tidak berada pada organisasi aktif.",AUTH_SESSION_REQUIRED:"Sesi Admin sudah berakhir.",BATCH_CONFIRMATION_REQUIRED:"Konfirmasi wajib dicentang."};const found=Object.entries(map).find(([code])=>raw.includes(code));return found?found[1]:"Aksi Batch gagal. Muat ulang dan coba kembali.";}
function batchDestination(kind:FeedbackKind,message:string,productId:string,batchId?:string){const q=new URLSearchParams({[kind]:message});return batchId?`/products/${productId}/batches/${batchId}?${q}`:`/products/${productId}?${q}#batches`;}
function batchDate(form:FormData,key:string,requiredValue=false){const v=optional(form,key);if(requiredValue&&!v)throw new Error('EXPIRY_DATE_REQUIRED');if(v&&!/^\\d{4}-\\d{2}-\\d{2}$/.test(v))throw new Error('INVALID_BATCH_DATE_RANGE');return v;}
function batchId(form:FormData){const v=required(form,'batchId');if(!UUID_PATTERN.test(v))throw new Error('BATCH_NOT_FOUND');return v;}
function batchVersion(form:FormData){const v=Number(required(form,'rowVersion'));if(!Number.isSafeInteger(v)||v<1)throw new Error('BATCH_STALE_VERSION');return v;}
export async function createProductBatchAction(form:FormData){const s=await requireAdminSession();const pid=productId(form);let k:FeedbackKind='success',m;try{const r=await (await import('@/lib/supabase-rest')).createProductBatch({organizationId:s.profile.organization_id,idempotencyKey:`product-batch-admin:create:${intentId(form)}`,productId:pid,batchCode:required(form,'batchCode'),expiryDate:batchDate(form,'expiryDate',true)!,manufacturedDate:batchDate(form,'manufacturedDate'),receivedFirstAt:optional(form,'receivedFirstAt'),note:optional(form,'note')});m=`Batch ${r.batchCode} dibuat sebagai STANDARD tanpa mengubah stok.`;revalidateProducts();}catch(e){k='error';m=batchErrorMessage(e)}redirect(batchDestination(k,m!,pid));}
async function mutateBatch(form:FormData,kind:'update'|'block'|'unblock'|'archive'|'reactivate'){const s=await requireAdminSession();const pid=productId(form);const bid=typeof form.get('batchId')==='string'?String(form.get('batchId')):undefined;let k:FeedbackKind='success',m;try{const id=batchId(form),version=batchVersion(form),key=`product-batch-admin:${kind}:${intentId(form)}`;let r;if(kind==='update'){r=await (await import('@/lib/supabase-rest')).updateProductBatch({organizationId:s.profile.organization_id,idempotencyKey:key,batchId:id,expectedRowVersion:version,productId:pid,batchCode:required(form,'batchCode'),manufacturedDate:batchDate(form,'manufacturedDate'),expiryDate:batchDate(form,'expiryDate',true)!,receivedFirstAt:optional(form,'receivedFirstAt'),reason:optional(form,'reason'),note:optional(form,'note')});m=`Batch ${r.batchCode} disimpan tanpa mengubah stok.`;}else{if(kind==='archive'||kind==='reactivate')requiresConfirmation(form);const input={organizationId:s.profile.organization_id,idempotencyKey:key,batchId:id,expectedRowVersion:version,reason:required(form,'reason'),note:optional(form,'note')};const api=await import('@/lib/supabase-rest');r=kind==='block'?await api.blockProductBatch(input):kind==='unblock'?await api.unblockProductBatch(input):kind==='archive'?await api.archiveProductBatch(input):await api.reactivateProductBatch(input);m=`Batch ${r.batchCode} berstatus ${r.lifecycleStatusCode}.`;}revalidateProducts();}catch(e){k='error';m=batchErrorMessage(e)}redirect(batchDestination(k,m!,pid,bid));}
export async function updateProductBatchAction(f:FormData){return mutateBatch(f,'update')} export async function blockProductBatchAction(f:FormData){return mutateBatch(f,'block')} export async function unblockProductBatchAction(f:FormData){return mutateBatch(f,'unblock')} export async function archiveProductBatchAction(f:FormData){return mutateBatch(f,'archive')} export async function reactivateProductBatchAction(f:FormData){return mutateBatch(f,'reactivate')}