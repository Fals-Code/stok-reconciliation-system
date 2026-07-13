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

function resultRedirect(kind: "success" | "error", message: string) {
  const params = new URLSearchParams({ [kind]: message });
  redirect(`/?${params.toString()}#actions`);
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
