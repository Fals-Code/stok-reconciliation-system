"use server";


import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdminSession } from "@/lib/auth";
import {
  callRpc,
  reserveMarketplaceListingEvent,
  shipMarketplaceListingEvent,
} from "@/lib/supabase-rest";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function positiveInteger(formData: FormData, key: string) {
  const raw = required(formData, key);
  const value = Number(raw);

  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${key} harus berupa bilangan bulat positif.`);
  }

  return value;
}

function nonnegativeInteger(formData: FormData, key: string) {
  const raw = required(formData, key);
  const value = Number(raw);

  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${key} harus berupa bilangan bulat nonnegatif.`);
  }

  return value;
}
function jakartaTimestamp(raw: string) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(raw)) {
    throw new Error("Waktu transaksi tidak valid.");
  }

  return `${raw}:00+07:00`;
}

function errorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "Terjadi kesalahan yang tidak diketahui.";
}

function receiptErrorMessage(error: unknown) {
  const raw = errorMessage(error);
  const messages: Record<string, string> = {
    RECEIPT_LINE_MASTER_NOT_FOUND:
      "Produk atau batch penerimaan tidak ditemukan pada organisasi aktif.",
    RECEIPT_PRODUCT_INACTIVE:
      "Produk sudah diarsipkan dan tidak dapat menerima transaksi baru.",
    RECEIPT_BATCH_NOT_ACTIVE:
      "Batch tidak aktif dan tidak dapat menerima transaksi baru.",
    RECEIPT_BATCH_EXPIRED:
      "Batch sudah kedaluwarsa dan tidak dapat menerima transaksi baru.",
    RECEIPT_BATCH_KIND_INVALID:
      "Penerimaan normal hanya dapat memakai batch standar.",
  };
  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}

function marketplaceErrorMessage(error: unknown) {
  const raw = errorMessage(error);
  const messages: Record<string, string> = {
    INSUFFICIENT_AVAILABLE_STOCK: "Stok available tidak mencukupi untuk reservasi tersebut.",
    INSUFFICIENT_FEFO_STOCK: "Stok batch yang memenuhi aturan FEFO tidak mencukupi untuk shipment.",
    MARKETPLACE_ORDER_ALREADY_EXISTS: "Order marketplace tersebut sudah pernah dibuat.",
    MARKETPLACE_EVENT_ALREADY_APPLIED: "Event marketplace tersebut sudah pernah diterapkan.",
    MARKETPLACE_ORDER_NOT_FOUND: "Order marketplace tidak ditemukan.",
    MARKETPLACE_ORDER_ITEM_NOT_FOUND: "Item reservasi pada order marketplace tidak ditemukan.",
    MARKETPLACE_RESERVATION_EXCEEDED: "Quantity melebihi sisa reservasi yang masih terbuka.",
    MARKETPLACE_CHANNEL_NOT_ALLOWED: "Channel tersebut bukan marketplace aktif.",
    MARKETPLACE_LISTING_NOT_FOUND: "Kode listing marketplace belum memiliki mapping aktif.",
    MARKETPLACE_LISTING_ARCHIVED: "Listing marketplace sudah diarsipkan.",
    MARKETPLACE_LISTING_MAPPING_NOT_FOUND: "Mapping produk untuk waktu event tidak ditemukan.",
    MARKETPLACE_LISTING_MAPPING_AMBIGUOUS: "Mapping listing bertumpang tindih dan harus diperbaiki.",
    MARKETPLACE_BUNDLE_RECIPE_NOT_FOUND: "Resep bundle aktif untuk waktu event tidak ditemukan.",
    MARKETPLACE_BUNDLE_RECIPE_AMBIGUOUS: "Versi resep bundle bertumpang tindih dan harus diperbaiki.",
    MARKETPLACE_LISTING_PRODUCT_INACTIVE: "Produk pada mapping listing sedang tidak aktif.",
    MARKETPLACE_BUNDLE_COMPONENT_INACTIVE: "Salah satu produk komponen bundle sedang tidak aktif.",
    MARKETPLACE_SOURCE_COMPONENT_NOT_FOUND: "Komponen order dari listing tersebut tidak ditemukan.",
    MARKETPLACE_SOURCE_COMPONENT_QUANTITY_EXCEEDED: "Quantity melebihi jumlah komponen hasil ekspansi order.",
    MARKETPLACE_SOURCE_STATUS_NOT_SHIPPABLE: "Status sumber belum memenuhi waktu pengurangan stok channel.",
    MARKETPLACE_RECEIVED_BEFORE_OCCURRED: "Waktu penerimaan event tidak boleh mendahului waktu kejadian.",
    RESERVATION_PROJECTION_MISMATCH: "Proyeksi reserved stock tidak konsisten dengan reservasi order.",
    IDEMPOTENCY_KEY_REUSED: "Referensi event sudah dipakai untuk payload yang berbeda.",
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched = Object.entries(messages).find(([code]) => raw.includes(code));
  return matched ? matched[1] : raw;
}

function returnErrorMessage(error: unknown) {
  const raw = errorMessage(error);
  const messages: Record<string, string> = {
    RETURN_ALREADY_EXISTS: "Referensi retur tersebut sudah pernah dibuat.",
    RETURN_ORDER_NOT_FOUND: "Order marketplace untuk retur tidak ditemukan.",
    RETURN_ORDER_ITEM_NOT_FOUND: "Item order marketplace untuk retur tidak ditemukan.",
    RETURN_ITEM_NOT_SHIPPED: "Item tersebut belum pernah dikirim.",
    RETURN_QUANTITY_EXCEEDS_SHIPPED: "Quantity retur melebihi quantity yang pernah dikirim.",
    RETURN_NOT_FOUND: "Retur tidak ditemukan.",
    RETURN_ITEM_NOT_FOUND: "Item retur tidak ditemukan.",
    RETURN_RECEIPT_EXCEEDS_PENDING: "Quantity penerimaan melebihi sisa retur yang belum diterima.",
    RETURN_SHIP_ALLOCATION_NOT_FOUND: "Alokasi shipment tidak cocok dengan item retur.",
    RETURN_RECEIPT_EXCEEDS_SHIP_ALLOCATION: "Quantity penerimaan melebihi alokasi shipment yang dipilih.",
    RETURN_RECEIPT_ALREADY_POSTED: "Referensi penerimaan retur sudah pernah diposting.",
    RETURN_RECEIPT_LINE_NOT_FOUND: "Baris penerimaan retur tidak ditemukan.",
    RETURN_INSPECTION_EXCEEDS_RECEIVED: "Quantity inspeksi melebihi jumlah diterima yang belum diperiksa.",
    RETURN_BATCH_IDENTITY_REQUIRED_FOR_SELLABLE: "Batch asal belum teridentifikasi sehingga hasil retur tidak boleh dimasukkan sebagai layak jual.",
    RETURN_SOURCE_BATCH_EXPIRED_FOR_SELLABLE: "Batch asal sudah kedaluwarsa sehingga hasil retur tidak dapat ditetapkan layak jual.",
    RETURN_BATCH_KIND_INVALID: "Batch tujuan retur tidak memiliki jenis batch retur yang valid.",
    RETURN_BATCH_NOT_ACTIVE_FOR_SELLABLE: "Batch retur tidak aktif sehingga tidak dapat menerima stok layak jual.",
    RETURN_BATCH_EXPIRED_FOR_SELLABLE: "Batch retur sudah kedaluwarsa sehingga tidak dapat menerima stok layak jual.",
    RETURN_SELLABLE_REASON_NOT_CONFIGURED: "Alasan pergerakan untuk retur layak jual belum dikonfigurasi.",
    RETURN_INSPECTION_ALREADY_POSTED: "Referensi inspeksi sudah pernah diposting.",
    RETURN_LOST_EXCEEDS_PENDING: "Quantity hilang melebihi sisa retur yang belum diterima.",
    RETURN_EVENT_ALREADY_APPLIED: "Referensi event retur sudah pernah diterapkan.",
    IDEMPOTENCY_KEY_REUSED: "Referensi sudah digunakan untuk payload yang berbeda.",
    ORGANIZATION_ACCESS_DENIED: "Retur tersebut berada di organisasi lain.",
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched = Object.entries(messages).find(([code]) => raw.includes(code));
  return matched ? matched[1] : raw;
}
function reconciliationErrorMessage(error: unknown) {
  const raw = errorMessage(error);
  const messages: Record<string, string> = {
    RECONCILIATION_CHECKS_REQUIRED:
      "Pilih minimal satu pemeriksaan rekonsiliasi.",
    RECONCILIATION_CHECK_CODE_DUPLICATE:
      "Daftar pemeriksaan mengandung kode duplikat.",
    RECONCILIATION_CHECK_NOT_SUPPORTED:
      "Terdapat pemeriksaan yang belum didukung.",
    RECONCILIATION_SCOPE_NOT_SUPPORTED:
      "Scope rekonsiliasi selain seluruh organisasi belum didukung.",
    IDEMPOTENCY_KEY_REUSED:
      "Permintaan rekonsiliasi memakai referensi yang sudah digunakan.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Permintaan rekonsiliasi yang sama masih diproses.",
    ORGANIZATION_ACCESS_DENIED:
      "Rekonsiliasi tidak dapat dijalankan untuk organisasi lain.",
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched = Object.entries(messages).find(([code]) => raw.includes(code));
  return matched ? matched[1] : raw;
}
function resultRedirect(
  kind: "success" | "error",
  message: string,
  destination: "actions" | "marketplace" | "returns" | "reconciliation" = "actions",
) {
  const params = new URLSearchParams({ [kind]: message });

  if (destination === "marketplace") {
    redirect(`/marketplace?${params.toString()}#simulator`);
  }

  if (destination === "returns") {
    redirect(`/returns?${params.toString()}#actions`);
  }

  if (destination === "reconciliation") {
    redirect(`/reconciliation?${params.toString()}#manual-run`);
  }
  redirect(`/?${params.toString()}#actions`);
}

function marketplaceChannel(formData: FormData) {
  const channelCode = required(formData, "channelCode").toUpperCase();

  if (!new Set(["SHOPEE", "TIKTOK_SHOP"]).has(channelCode)) {
    throw new Error("Channel marketplace tidak valid.");
  }

  return channelCode;
}

type MarketplaceChannelCode = "SHOPEE" | "TIKTOK_SHOP";

type MarketplaceListingSelection = {
  channelCode: MarketplaceChannelCode;
  externalListingCode: string;
  listingName: string;
  listingType: "SINGLE" | "BUNDLE";
};

type MarketplaceSelection = {
  channelCode: MarketplaceChannelCode;
  orderRef: string;
  orderSourceLineRef: string;
  componentNo: number;
};

function parsedObject(formData: FormData, key: string, message: string) {
  const raw = required(formData, key);
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(message);
  }

  if (!parsed || typeof parsed !== "object") {
    throw new Error(message);
  }

  return parsed as Record<string, unknown>;
}

function marketplaceListingSelection(
  formData: FormData,
): MarketplaceListingSelection {
  const value = parsedObject(
    formData,
    "marketplaceListingSelection",
    "Pilihan listing marketplace tidak valid.",
  );
  const channelCode = String(value.channelCode ?? "")
    .trim()
    .toUpperCase();
  const listingType = String(value.listingType ?? "")
    .trim()
    .toUpperCase();
  const externalListingCode = String(value.externalListingCode ?? "").trim();
  const listingName = String(value.listingName ?? "").trim();

  if (!new Set(["SHOPEE", "TIKTOK_SHOP"]).has(channelCode)) {
    throw new Error("Channel listing marketplace tidak valid.");
  }

  if (!new Set(["SINGLE", "BUNDLE"]).has(listingType)) {
    throw new Error("Jenis listing marketplace tidak valid.");
  }

  if (!externalListingCode || !listingName) {
    throw new Error("Pilihan listing marketplace tidak lengkap.");
  }

  return {
    channelCode: channelCode as MarketplaceChannelCode,
    externalListingCode,
    listingName,
    listingType: listingType as "SINGLE" | "BUNDLE",
  };
}

function marketplaceSelection(formData: FormData): MarketplaceSelection {
  const value = parsedObject(
    formData,
    "marketplaceSelection",
    "Pilihan komponen marketplace tidak valid.",
  );
  const channelCode = String(value.channelCode ?? "")
    .trim()
    .toUpperCase();
  const orderRef = String(value.orderRef ?? "").trim();
  const orderSourceLineRef = String(value.orderSourceLineRef ?? "").trim();
  const componentNo = Number(value.componentNo);

  if (!new Set(["SHOPEE", "TIKTOK_SHOP"]).has(channelCode)) {
    throw new Error("Channel komponen marketplace tidak valid.");
  }

  if (!orderRef || !orderSourceLineRef) {
    throw new Error("Pilihan komponen marketplace tidak lengkap.");
  }

  if (!Number.isSafeInteger(componentNo) || componentNo <= 0) {
    throw new Error("Nomor komponen marketplace tidak valid.");
  }

  return {
    channelCode: channelCode as MarketplaceChannelCode,
    orderRef,
    orderSourceLineRef,
    componentNo,
  };
}

export async function postReceiptAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const sourceRef = required(formData, "sourceRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const batchSelection = required(formData, "batchSelection");
    const [productId, batchId] = batchSelection.split(":");
    const quantity = positiveInteger(formData, "quantity");
    const note = String(formData.get("note") ?? "").trim() || null;

    if (!productId || !batchId) {
      throw new Error("Pilihan batch tidak valid.");
    }

    const result = await callRpc<{
      receiptNo: string;
      totalQuantity: number;
    }>("post_receipt", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `receipt:${sourceRef}`,
      p_source_ref: sourceRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          productId,
          batchId,
          quantity,
          sourceLineRef: "UI-1",
        },
      ],
      p_note: note,
      p_metadata: {
        source: "dashboard",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = `${result.receiptNo} berhasil menambah ${result.totalQuantity} unit.`;
    revalidatePath("/");
  } catch (error) {
    kind = "error";
    message = receiptErrorMessage(error);
  }

  resultRedirect(kind, message);
}

export async function reserveMarketplaceOrderAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const selection = marketplaceListingSelection(formData);
    const orderRef = required(formData, "orderRef");
    const eventRef = required(formData, "eventRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const sourceLineRef = required(formData, "sourceLineRef");
    const listingQuantity = positiveInteger(formData, "listingQuantity");
    const note = String(formData.get("note") ?? "").trim() || null;
    const sourceStatus = "READY_TO_SHIP";

    const result = await reserveMarketplaceListingEvent({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-reserve:${selection.channelCode}:${eventRef}`,
      channelCode: selection.channelCode,
      eventRef,
      orderRef,
      sourceStatus,
      occurredAt,
      receivedAt: occurredAt,
      lines: [
        {
          sourceLineRef,
          externalListingCode: selection.externalListingCode,
          listingQuantity,
          sourceTitle: selection.listingName,
          sourceSku: selection.externalListingCode,
          sourceStatus,
          rawLinePayload: {
            source: "marketplace-listing-simulator",
            sourceLineRef,
          },
        },
      ],
      note,
      rawPayload: {
        channelCode: selection.channelCode,
        eventRef,
        orderRef,
        sourceStatus,
        externalListingCode: selection.externalListingCode,
        listingQuantity,
      },
      metadata: {
        source: "marketplace-listing-simulator",
        version: 1,
        actorUserId: session.user.id,
      },
      schemaVersion: 1,
    });

    const canonicalLineCount = Number(result.canonicalLineCount ?? 0);
    const totalUnitQuantity = Number(
      result.totalUnitQuantity ?? result.totalQuantity ?? 0,
    );
    message =
      `${result.orderRef} menormalisasi ${selection.externalListingCode} ` +
      `menjadi ${canonicalLineCount} komponen dan mereservasi ` +
      `${totalUnitQuantity} unit tanpa mengubah stok fisik.`;
    revalidatePath("/");
    revalidatePath("/marketplace");
  } catch (error) {
    kind = "error";
    message = marketplaceErrorMessage(error);
  }

  resultRedirect(kind, message, "marketplace");
}

export async function advanceMarketplaceOrderAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const selection = marketplaceSelection(formData);
    const eventRef = required(formData, "eventRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const quantity = positiveInteger(formData, "quantity");
    const note = String(formData.get("note") ?? "").trim() || null;
    const sourceStatus =
      selection.channelCode === "SHOPEE" ? "SHIPPED" : "IN_TRANSIT";

    const result = await shipMarketplaceListingEvent({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-ship:${selection.channelCode}:${eventRef}`,
      channelCode: selection.channelCode,
      eventRef,
      orderRef: selection.orderRef,
      sourceStatus,
      occurredAt,
      receivedAt: occurredAt,
      lines: [
        {
          orderSourceLineRef: selection.orderSourceLineRef,
          componentNo: selection.componentNo,
          quantity,
        },
      ],
      note,
      rawPayload: {
        channelCode: selection.channelCode,
        eventRef,
        orderRef: selection.orderRef,
        sourceStatus,
        orderSourceLineRef: selection.orderSourceLineRef,
        componentNo: selection.componentNo,
        quantity,
      },
      metadata: {
        source: "marketplace-listing-simulator",
        version: 1,
        actorUserId: session.user.id,
      },
      schemaVersion: 1,
    });

    message =
      `${result.transactionNo ?? result.orderRef} mengirim ` +
      `${Number(result.totalQuantity ?? 0)} unit melalui ` +
      `${Number(result.allocationCount ?? 0)} alokasi batch FEFO.`;
    revalidatePath("/");
    revalidatePath("/marketplace");
  } catch (error) {
    kind = "error";
    message = marketplaceErrorMessage(error);
  }

  resultRedirect(kind, message, "marketplace");
}
export async function createExpectedReturnAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const channelCode = marketplaceChannel(formData);
    const returnRef = required(formData, "returnRef");
    const orderRef = required(formData, "orderRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const productId = required(formData, "productId");
    const sourceLineRef = required(formData, "sourceLineRef");
    const quantity = positiveInteger(formData, "quantity");
    const sourceStatus = String(formData.get("sourceStatus") ?? "").trim() || null;
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<{
      returnRef: string;
      totalQuantity: number;
      status: string;
    }>("create_expected_return", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `return:expected:${returnRef}`,
      p_channel_code: channelCode,
      p_return_ref: returnRef,
      p_order_ref: orderRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          productId,
          quantity,
          sourceLineRef,
        },
      ],
      p_source_status: sourceStatus,
      p_note: note,
      p_metadata: {
        source: "return-admin",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = `${result.returnRef} dibuat sebagai expected return untuk ${result.totalQuantity} unit.`;
    revalidatePath("/marketplace");
    revalidatePath("/returns");
  } catch (error) {
    kind = "error";
    message = returnErrorMessage(error);
  }

  resultRedirect(kind, message, "returns");
}

export async function confirmReturnReceiptAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const returnRef = required(formData, "returnRef");
    const receiptRef = required(formData, "receiptRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const returnItemId = required(formData, "returnItemId");
    const quantity = positiveInteger(formData, "quantity");
    const sourceLineRef = required(formData, "sourceLineRef");
    const marketplaceShipAllocationId =
      String(formData.get("marketplaceShipAllocationId") ?? "").trim() || null;
    const note = String(formData.get("note") ?? "").trim() || null;

    const line: Record<string, unknown> = {
      returnItemId,
      quantity,
      sourceLineRef,
    };

    if (marketplaceShipAllocationId) {
      line.marketplaceShipAllocationId = marketplaceShipAllocationId;
    }

    const result = await callRpc<{
      returnRef: string;
      receiptRef: string;
      transactionNo: string | null;
      stockEffectCode: "NONE";
      totalQuantity: number;
      status: string;
    }>("confirm_return_receipt", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `return:receipt:${receiptRef}`,
      p_return_ref: returnRef,
      p_receipt_ref: receiptRef,
      p_occurred_at: occurredAt,
      p_lines: [line],
      p_note: note,
      p_metadata: {
        source: "return-admin",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message =
      `${result.receiptRef} mencatat penerimaan fisik ${result.totalQuantity} unit. ` +
      "Stok belum berubah sebelum hasil inspeksi ditetapkan.";
    revalidatePath("/");
    revalidatePath("/returns");
  } catch (error) {
    kind = "error";
    message = returnErrorMessage(error);
  }

  resultRedirect(kind, message, "returns");
}

export async function inspectReturnAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const returnRef = required(formData, "returnRef");
    const inspectionRef = required(formData, "inspectionRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const receiptLineId = required(formData, "receiptLineId");
    const sellableQuantity = nonnegativeInteger(formData, "sellableQuantity");
    const damagedQuantity = nonnegativeInteger(formData, "damagedQuantity");
    const sourceLineRef = required(formData, "sourceLineRef");
    const note = String(formData.get("note") ?? "").trim() || null;

    if (sellableQuantity + damagedQuantity <= 0) {
      throw new Error("Minimal satu quantity inspeksi harus lebih dari nol.");
    }

    const result = await callRpc<{
      inspectionRef: string;
      transactionNo: string | null;
      stockEffectCode: "NONE" | "SELLABLE_INBOUND";
      totalQuantity: number;
      sellableQuantity: number;
      damagedQuantity: number;
      status: string;
    }>("inspect_return", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `return:inspection:${inspectionRef}`,
      p_return_ref: returnRef,
      p_inspection_ref: inspectionRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          receiptLineId,
          sellableQuantity,
          damagedQuantity,
          sourceLineRef,
        },
      ],
      p_note: note,
      p_metadata: {
        source: "return-admin",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    if (result.sellableQuantity > 0) {
      const transactionLabel = result.transactionNo ?? result.inspectionRef;
      const damagedNote =
        result.damagedQuantity > 0
          ? ` ${result.damagedQuantity} unit rusak dicatat tanpa pergerakan stok.`
          : "";

      message =
        `${transactionLabel} menambah ${result.sellableQuantity} unit layak jual ` +
        `ke batch retur baru.${damagedNote}`;
    } else {
      message =
        `${result.inspectionRef} mencatat ${result.damagedQuantity} unit rusak ` +
        "tanpa pergerakan stok.";
    }
    revalidatePath("/");
    revalidatePath("/returns");
  } catch (error) {
    kind = "error";
    message = returnErrorMessage(error);
  }

  resultRedirect(kind, message, "returns");
}

export async function markReturnLostAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const returnRef = required(formData, "returnRef");
    const eventRef = required(formData, "eventRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const returnItemId = required(formData, "returnItemId");
    const quantity = positiveInteger(formData, "quantity");
    const sourceLineRef = required(formData, "sourceLineRef");
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<{
      returnRef: string;
      eventRef: string;
      totalQuantity: number;
      status: string;
    }>("mark_return_lost", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `return:lost:${eventRef}`,
      p_return_ref: returnRef,
      p_event_ref: eventRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          returnItemId,
          quantity,
          sourceLineRef,
        },
      ],
      p_note: note,
      p_metadata: {
        source: "return-admin",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = `${result.returnRef} menandai ${result.totalQuantity} unit sebagai lost.`;
    revalidatePath("/returns");
  } catch (error) {
    kind = "error";
    message = returnErrorMessage(error);
  }

  resultRedirect(kind, message, "returns");
}
const RECONCILIATION_CHECK_CODES = [
  "LEDGER_BATCH_PROJECTION",
  "BATCH_PRODUCT_PROJECTION",
  "RESERVATION_CONSISTENCY",
  "MARKETPLACE_ALLOCATION_CONSISTENCY",
  "RETURN_RECEIPT_CONSISTENCY",
  "RETURN_INSPECTION_CONSISTENCY",
  "DUPLICATE_SOURCE_EFFECT",
  "IMPOSSIBLE_PROJECTION_STATE",
] as const;

function reconciliationCheckCodes(formData: FormData) {
  const values = formData
    .getAll("checkCodes")
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim().toUpperCase())
    .filter(Boolean);

  if (values.length === 0) {
    throw new Error("RECONCILIATION_CHECKS_REQUIRED");
  }

  if (new Set(values).size !== values.length) {
    throw new Error("RECONCILIATION_CHECK_CODE_DUPLICATE");
  }

  const supported = new Set<string>(RECONCILIATION_CHECK_CODES);
  if (values.some((value) => !supported.has(value))) {
    throw new Error("RECONCILIATION_CHECK_NOT_SUPPORTED");
  }

  return values;
}

export async function runReconciliationAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const checkCodes = reconciliationCheckCodes(formData);
    const idempotencyKey = required(formData, "idempotencyKey");

    const result = await callRpc<{
      status: string;
      integrityStatus: string;
      runId: string;
      runNo: string;
      ruleSetVersion: string;
      ledgerSeqFrom: number;
      ledgerSeqTo: number;
      checkCount: number;
      issueCount: number;
    }>("run_reconciliation", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: idempotencyKey,
      p_check_codes: checkCodes,
      p_scope: {},
      p_metadata: {
        source: "reconciliation-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message =
      `${result.runNo} selesai dengan status ${result.integrityStatus}. ` +
      `Boundary ledger ${result.ledgerSeqFrom}-${result.ledgerSeqTo}, ` +
      `${result.issueCount} issue dari ${result.checkCount} check.`;

    revalidatePath("/reconciliation");
  } catch (error) {
    kind = "error";
    message = reconciliationErrorMessage(error);
  }

  resultRedirect(kind, message, "reconciliation");
}
