"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdminSession } from "@/lib/auth";
import { callRpc } from "@/lib/supabase-rest";

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
    RESERVATION_PROJECTION_MISMATCH: "Proyeksi reserved stock tidak konsisten dengan reservasi order.",
    IDEMPOTENCY_KEY_REUSED: "Referensi event sudah dipakai untuk payload yang berbeda.",
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched = Object.entries(messages).find(([code]) => raw.includes(code));
  return matched ? matched[1] : raw;
}

function resultRedirect(
  kind: "success" | "error",
  message: string,
  destination: "actions" | "marketplace" = "actions",
) {
  const params = new URLSearchParams({ [kind]: message });

  if (destination === "marketplace") {
    redirect(`/marketplace?${params.toString()}#simulator`);
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

type MarketplaceSelection = {
  channelCode: string;
  orderRef: string;
  productId: string;
  sourceLineRef: string;
};

function marketplaceSelection(formData: FormData): MarketplaceSelection {
  const raw = required(formData, "marketplaceSelection");
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("Pilihan reservasi marketplace tidak valid.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new Error("Pilihan reservasi marketplace tidak valid.");
  }

  const value = parsed as Record<string, unknown>;
  const keys = ["channelCode", "orderRef", "productId", "sourceLineRef"] as const;

  for (const key of keys) {
    if (typeof value[key] !== "string" || value[key].trim() === "") {
      throw new Error("Pilihan reservasi marketplace tidak lengkap.");
    }
  }

  return {
    channelCode: String(value.channelCode).trim().toUpperCase(),
    orderRef: String(value.orderRef).trim(),
    productId: String(value.productId).trim(),
    sourceLineRef: String(value.sourceLineRef).trim(),
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
    message = errorMessage(error);
  }

  resultRedirect(kind, message);
}

export async function postManualOutboundAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const sourceRef = required(formData, "sourceRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const productId = required(formData, "productId");
    const reasonCode = required(formData, "reasonCode");
    const quantity = positiveInteger(formData, "quantity");
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<{
      outboundNo: string;
      totalQuantity: number;
      allocationCount: number;
    }>("post_manual_outbound", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `outbound:${sourceRef}`,
      p_source_ref: sourceRef,
      p_occurred_at: occurredAt,
      p_reason_code: reasonCode,
      p_lines: [
        {
          productId,
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

    message = `${result.outboundNo} berhasil mengeluarkan ${result.totalQuantity} unit melalui ${result.allocationCount} batch FEFO.`;
    revalidatePath("/");
  } catch (error) {
    kind = "error";
    message = errorMessage(error);
  }

  resultRedirect(kind, message);
}

export async function reserveMarketplaceOrderAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const channelCode = marketplaceChannel(formData);
    const orderRef = required(formData, "orderRef");
    const eventRef = required(formData, "eventRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const productId = required(formData, "productId");
    const sourceLineRef = required(formData, "sourceLineRef");
    const quantity = positiveInteger(formData, "quantity");
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<{
      orderRef: string;
      eventType: string;
      totalQuantity: number;
      allocationCount: number;
    }>("apply_marketplace_event", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `marketplace:${channelCode}:${eventRef}`,
      p_channel_code: channelCode,
      p_event_type: "RESERVE",
      p_event_ref: eventRef,
      p_order_ref: orderRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          productId,
          quantity,
          sourceLineRef,
        },
      ],
      p_note: note,
      p_metadata: {
        source: "marketplace-simulator",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = `${result.orderRef} berhasil mereservasi ${result.totalQuantity} unit tanpa mengubah stok fisik.`;
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
    const eventType = required(formData, "eventType").toUpperCase();

    if (!new Set(["RELEASE", "SHIP"]).has(eventType)) {
      throw new Error("Jenis event marketplace tidak valid.");
    }

    const selection = marketplaceSelection(formData);
    const eventRef = required(formData, "eventRef");
    const occurredAt = jakartaTimestamp(required(formData, "occurredAt"));
    const quantity = positiveInteger(formData, "quantity");
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<{
      orderRef: string;
      eventType: string;
      totalQuantity: number;
      allocationCount: number;
      transactionNo: string | null;
    }>("apply_marketplace_event", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `marketplace:${selection.channelCode}:${eventRef}`,
      p_channel_code: selection.channelCode,
      p_event_type: eventType,
      p_event_ref: eventRef,
      p_order_ref: selection.orderRef,
      p_occurred_at: occurredAt,
      p_lines: [
        {
          productId: selection.productId,
          quantity,
          sourceLineRef: selection.sourceLineRef,
        },
      ],
      p_note: note,
      p_metadata: {
        source: "marketplace-simulator",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message = eventType === "RELEASE"
      ? `${result.orderRef} berhasil melepas ${result.totalQuantity} unit dari reservasi.`
      : `${result.transactionNo ?? result.orderRef} berhasil mengirim ${result.totalQuantity} unit melalui ${result.allocationCount} batch FEFO.`;

    revalidatePath("/");
    revalidatePath("/marketplace");
  } catch (error) {
    kind = "error";
    message = marketplaceErrorMessage(error);
  }

  resultRedirect(kind, message, "marketplace");
}
