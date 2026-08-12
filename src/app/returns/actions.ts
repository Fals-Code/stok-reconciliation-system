"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import { safeInternalRoute } from "@/lib/safe-internal-route";
import {
  cancelTikTokReturnClaim,
  confirmLateReturnArrival,
  confirmReturnReceipt,
  createTikTokReturnClaim,
  inspectReturn,
  markReturnLost,
  resolveTikTokReturnClaim,
  submitTikTokReturnClaim,
} from "@/lib/supabase-rest";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function required(form: FormData, key: string) {
  const value = form.get(key);
  if (typeof value !== "string" || !value.trim()) throw new Error(`${key} wajib diisi.`);
  return value.trim();
}

function uuid(form: FormData, key: string) {
  const value = required(form, key);
  if (!UUID.test(value)) throw new Error(`${key} tidak valid.`);
  return value;
}

function positive(value: string, label: string) {
  if (!/^[1-9][0-9]*$/.test(value)) throw new Error(`${label} harus berupa bilangan bulat positif.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new Error(`${label} terlalu besar.`);
  return parsed;
}

function occurredAt(form: FormData) {
  const value = required(form, "occurredAt");
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new Error("Waktu harus memakai format WIB yang valid.");
  return `${value}:00+07:00`;
}

function confirmed(form: FormData) {
  if (form.get("confirmation") !== "on") throw new Error("Konfirmasi operator wajib dicentang.");
}

function message(error: unknown) {
  const raw = error instanceof Error ? error.message : "Terjadi kesalahan yang tidak diketahui.";
  const map: Record<string, string> = {
    AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTHENTICATION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
    ORGANIZATION_ACCESS_DENIED: "Data tersebut tidak berada pada organisasi aktif.",
    TIKTOK_RETURN_NOT_FOUND: "Retur TikTok tidak ditemukan atau tidak dapat diklaim.",
    RETURN_CLAIM_REQUEST_INVALID: "Permintaan klaim tidak lengkap.",
    RETURN_CLAIM_TYPE_INVALID: "Jenis klaim tidak didukung.",
    RETURN_CLAIM_DUPLICATE_ITEM: "Satu item retur hanya boleh dipilih sekali.",
    RETURN_CLAIM_ITEM_INVALID: "Quantity klaim harus bilangan bulat positif.",
    RETURN_CLAIM_ITEM_NOT_ELIGIBLE: "Item bukan quantity hilang yang masih eligible.",
    RETURN_CLAIM_ITEM_CAPACITY_EXCEEDED: "Sisa quantity yang masih dapat diklaim tidak mencukupi.",
    RETURN_CLAIM_NOT_FOUND: "Klaim tidak ditemukan dalam organisasi aktif.",
    RETURN_CLAIM_SUBMIT_INVALID: "Klaim belum berada pada status yang dapat dikirim.",
    RETURN_CLAIM_RESOLVE_INVALID: "Klaim belum berada pada status yang dapat diselesaikan.",
    RETURN_CLAIM_CANCEL_INVALID: "Klaim belum berada pada status yang dapat dibatalkan.",
    RETURN_CLAIM_PROVENANCE_AMBIGUOUS: "Provenance bundle historis memiliki lebih dari satu komponen yang cocok.",
    RETURN_CLAIM_BUNDLE_PROVENANCE_MISSING: "Provenance bundle historis tidak lengkap.",
    IDEMPOTENCY_KEY_REUSED: "Referensi perintah sudah dipakai untuk payload berbeda.",
    RETURN_LATE_ARRIVAL_REQUEST_INVALID: "Data kedatangan terlambat belum lengkap.",
    RETURN_LATE_ARRIVAL_LINE_INVALID: "Baris kedatangan terlambat tidak valid.",
    RETURN_LATE_ARRIVAL_DUPLICATE_ITEM: "Item kedatangan terlambat tidak boleh duplikat.",
    RETURN_LATE_ARRIVAL_ALREADY_POSTED: "Referensi kedatangan atau receipt sudah pernah diproses.",
    RETURN_ITEM_NOT_FOUND: "Item retur tidak ditemukan.",
    RETURN_LATE_ARRIVAL_EXCEEDS_NET_LOST: "Kedatangan terlambat melebihi quantity lost yang belum dikoreksi.",
    RETURN_LATE_ARRIVAL_ALLOCATION_INVALID: "Batch asal kiriman tidak cocok dengan item retur.",
    RETURN_LATE_ARRIVAL_ALLOCATION_CAPACITY_EXCEEDED: "Quantity melebihi kapasitas shipment yang masih dapat direferensikan.",
  };
  const match = Object.entries(map).find(([code]) => raw.includes(code));
  return match?.[1] ?? raw;
}

function destination(form: FormData, kind: "success" | "error", text: string) {
  const params = new URLSearchParams();
  const returnId = String(form.get("returnId") ?? "").trim();
  const claimId = String(form.get("claimId") ?? "").trim();
  const returnTo = safeInternalRoute(
    String(form.get("returnTo") ?? ""),
    "/returns",
    { allowedPathnames: ["/returns"] },
  );

  if (claimId && UUID.test(claimId)) {
    params.set("claimId", claimId);
  }

  if (returnTo !== "/returns") {
    params.set("returnTo", returnTo);
  }

  params.set(kind, text);

  const basePath =
    returnId && UUID.test(returnId)
      ? `/returns/${encodeURIComponent(returnId)}`
      : "/returns";

  redirect(
    `${basePath}?${params.toString()}#${
      claimId ? "claim-detail" : "return-actions"
    }`,
  );
}

export async function createTikTokReturnClaimAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Klaim berhasil dibuat.";
  try {
    confirmed(form);
    const returnId = uuid(form, "returnId");
    const key = required(form, "idempotencyKey");
    const claimTypeCode = required(form, "claimTypeCode");
    const selected = form.getAll("claimItemId").filter((v): v is string => typeof v === "string");
    if (!selected.length) throw new Error("Pilih minimal satu barang hilang.");
    const seen = new Set<string>();
    const items = selected.map((itemId) => {
      if (!UUID.test(itemId) || seen.has(itemId)) throw new Error("Item klaim duplikat atau tidak valid.");
      seen.add(itemId);
      return { returnItemId: itemId, quantity: positive(required(form, `quantity_${itemId}`), "Quantity klaim") };
    });
    const result = await createTikTokReturnClaim({
      organizationId: session.profile.organization_id,
      idempotencyKey: key,
      returnId,
      claimTypeCode,
      items,
      occurredAt: occurredAt(form),
    });
    text = `Klaim ${result.claimId} berhasil dibuat. Stok tidak berubah.`;
  } catch (error) { kind = "error"; text = message(error); }
  revalidatePath("/returns");
  revalidatePath("/notifications");
  destination(form, kind, text);
}

export async function submitTikTokReturnClaimAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Klaim berhasil dikirim.";
  try {
    confirmed(form);
    const claimId = uuid(form, "claimId");
    const externalClaimRef = required(form, "externalClaimRef");
    const result = await submitTikTokReturnClaim({ organizationId: session.profile.organization_id, claimId, externalClaimRef, idempotencyKey: `returns:claim:submit:${claimId}:${externalClaimRef}`, occurredAt: occurredAt(form) });
    text = `Klaim ${result.claimId} berhasil ditandai sudah dikirim. Stok tidak berubah.`;
  } catch (error) { kind = "error"; text = message(error); }
  revalidatePath("/returns"); revalidatePath("/notifications"); destination(form, kind, text);
}

export async function resolveTikTokReturnClaimAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Klaim berhasil diselesaikan.";
  try {
    confirmed(form);
    const claimId = uuid(form, "claimId");
    const resolutionCode = required(form, "resolutionCode");
    const result = await resolveTikTokReturnClaim({ organizationId: session.profile.organization_id, claimId, resolutionCode, idempotencyKey: `returns:claim:resolve:${claimId}:${resolutionCode}`, occurredAt: occurredAt(form) });
    text = `Klaim ${result.claimId} berhasil diselesaikan. Stok tidak berubah.`;
  } catch (error) { kind = "error"; text = message(error); }
  revalidatePath("/returns"); revalidatePath("/notifications"); destination(form, kind, text);
}

export async function cancelTikTokReturnClaimAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Klaim berhasil dibatalkan.";
  try {
    confirmed(form);
    const claimId = uuid(form, "claimId");
    const reason = required(form, "reason");
    const result = await cancelTikTokReturnClaim({ organizationId: session.profile.organization_id, claimId, reason, idempotencyKey: `returns:claim:cancel:${claimId}:${reason}`, occurredAt: occurredAt(form) });
    text = `Klaim ${result.claimId} berhasil dibatalkan. Stok tidak berubah.`;
  } catch (error) { kind = "error"; text = message(error); }
  revalidatePath("/returns"); revalidatePath("/notifications"); destination(form, kind, text);
}

export async function confirmLateReturnArrivalAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Kedatangan terlambat berhasil dicatat.";
  try {
    confirmed(form);
    const returnId = uuid(form, "returnId");
    const returnRef = required(form, "returnRef");
    const lateArrivalReference = required(form, "lateArrivalReference");
    const receiptRef = required(form, "receiptRef");
    const selected = form.getAll("lateReturnLineKey").filter((v): v is string => typeof v === "string");
    if (!selected.length) throw new Error("Pilih minimal satu line item lost.");
    const seen = new Set<string>();
    const lines = selected.map((lineKey) => {
      const separator = lineKey.indexOf(":");
      const itemId = separator > 0 ? lineKey.slice(0, separator) : lineKey;
      const allocationToken = separator > 0 ? lineKey.slice(separator + 1) : "UNVERIFIED";
      const allocationId = allocationToken === "UNVERIFIED" ? null : allocationToken;
      const compositeKey = `${itemId}:${allocationId ?? "UNVERIFIED"}`;
      if (!UUID.test(itemId) || (allocationId && !UUID.test(allocationId)) || seen.has(compositeKey)) throw new Error("Line kedatangan duplikat atau tidak valid.");
      seen.add(compositeKey);
      return { returnItemId: itemId, quantity: positive(required(form, `lateQuantity_${lineKey}`), "Quantity kedatangan"), marketplaceShipAllocationId: allocationId };
    }).sort((left, right) => `${left.returnItemId}:${left.marketplaceShipAllocationId ?? "UNVERIFIED"}`.localeCompare(`${right.returnItemId}:${right.marketplaceShipAllocationId ?? "UNVERIFIED"}`));
    const sourceLineRef = required(form, "sourceLineRef");
    const result = await confirmLateReturnArrival({
      organizationId: session.profile.organization_id,
      idempotencyKey: `returns:late-arrival:${lateArrivalReference}`,
      returnRef,
      lateArrivalReference,
      receiptRef,
      occurredAt: occurredAt(form),
      lines,
      note: String(form.get("note") ?? "").trim() || null,
      metadata: { source: "returns-admin", version: 1, actorUserId: session.user.id, returnId, sourceLineRef },
    });
    text = `${receiptRef} mencatat ${result.totalQuantity} unit. Receipt tetap stock-neutral (NONE).`;
  } catch (error) { kind = "error"; text = message(error); }
  revalidatePath("/returns"); revalidatePath("/notifications"); revalidatePath("/"); destination(form, kind, text);
}

export async function confirmReturnReceiptAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Kedatangan retur berhasil dicatat.";

  try {
    confirmed(form);
    const returnId = uuid(form, "returnId");
    const returnRef = required(form, "returnRef");
    const receiptRef = required(form, "receiptRef");
    const selected = form
      .getAll("receiptLineKey")
      .filter((value): value is string => typeof value === "string");

    if (!selected.length) {
      throw new Error("Pilih minimal satu item yang datang.");
    }

    const seen = new Set<string>();
    const lines = selected
      .map((lineKey, index) => {
        const separator = lineKey.indexOf(":");
        const returnItemId =
          separator > 0 ? lineKey.slice(0, separator) : lineKey;
        const allocationToken =
          separator > 0
            ? lineKey.slice(separator + 1)
            : "UNVERIFIED";
        const marketplaceShipAllocationId =
          allocationToken === "UNVERIFIED"
            ? null
            : allocationToken;
        const compositeKey =
          `${returnItemId}:${
            marketplaceShipAllocationId ?? "UNVERIFIED"
          }`;

        if (
          !UUID.test(returnItemId) ||
          (marketplaceShipAllocationId &&
            !UUID.test(marketplaceShipAllocationId)) ||
          seen.has(compositeKey)
        ) {
          throw new Error(
            "Item atau provenance kedatangan duplikat/tidak valid.",
          );
        }

        seen.add(compositeKey);

        return {
          returnItemId,
          quantity: positive(
            required(form, `receiptQuantity_${lineKey}`),
            "Quantity kedatangan",
          ),
          sourceLineRef: `RETURN-RECEIPT-${index + 1}`,
          marketplaceShipAllocationId,
        };
      })
      .sort((left, right) =>
        `${left.returnItemId}:${
          left.marketplaceShipAllocationId ?? "UNVERIFIED"
        }`.localeCompare(
          `${right.returnItemId}:${
            right.marketplaceShipAllocationId ?? "UNVERIFIED"
          }`,
        ),
      );

    const result = await confirmReturnReceipt({
      organizationId: session.profile.organization_id,
      idempotencyKey: `returns:receipt:${receiptRef}`,
      returnRef,
      receiptRef,
      occurredAt: occurredAt(form),
      lines,
      note: String(form.get("note") ?? "").trim() || null,
      metadata: {
        source: "returns-admin",
        version: 2,
        actorUserId: session.user.id,
        returnId,
      },
    });

    text = `${receiptRef} mencatat ${result.totalQuantity} unit datang. Kedatangan tetap tidak mengubah stok.`;
  } catch (error) {
    kind = "error";
    text = message(error);
  }

  revalidatePath("/returns");
  revalidatePath("/");
  destination(form, kind, text);
}

export async function inspectReturnAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Pemeriksaan retur berhasil dicatat.";

  try {
    confirmed(form);
    const returnId = uuid(form, "returnId");
    const returnRef = required(form, "returnRef");
    const inspectionRef = required(form, "inspectionRef");
    const selected = form
      .getAll("inspectionReceiptLineId")
      .filter((value): value is string => typeof value === "string");

    if (!selected.length) {
      throw new Error("Pilih minimal satu kedatangan yang diperiksa.");
    }

    const seen = new Set<string>();
    const lines = selected.map((receiptLineId, index) => {
      if (!UUID.test(receiptLineId) || seen.has(receiptLineId)) {
        throw new Error("Baris pemeriksaan duplikat atau tidak valid.");
      }

      seen.add(receiptLineId);

      return {
        receiptLineId,
        sellableQuantity: Number(
          String(
            form.get(`sellableQuantity_${receiptLineId}`) ?? "0",
          ),
        ),
        damagedQuantity: Number(
          String(
            form.get(`damagedQuantity_${receiptLineId}`) ?? "0",
          ),
        ),
        sourceLineRef: `RETURN-INSPECTION-${index + 1}`,
      };
    });

    for (const line of lines) {
      if (
        !Number.isSafeInteger(line.sellableQuantity) ||
        line.sellableQuantity < 0 ||
        !Number.isSafeInteger(line.damagedQuantity) ||
        line.damagedQuantity < 0 ||
        line.sellableQuantity + line.damagedQuantity <= 0
      ) {
        throw new Error(
          "Quantity layak jual dan rusak harus bilangan bulat non-negatif, dengan total lebih dari nol.",
        );
      }
    }

    const result = await inspectReturn({
      organizationId: session.profile.organization_id,
      idempotencyKey: `returns:inspection:${inspectionRef}`,
      returnRef,
      inspectionRef,
      occurredAt: occurredAt(form),
      lines,
      note: String(form.get("note") ?? "").trim() || null,
      metadata: {
        source: "returns-admin",
        version: 2,
        actorUserId: session.user.id,
        returnId,
      },
    });

    text =
      result.sellableQuantity > 0
        ? `${inspectionRef} selesai. ${result.sellableQuantity} unit layak jual masuk ke batch retur baru; ${result.damagedQuantity} unit rusak hanya dicatat sebagai kondisi fisik.`
        : `${inspectionRef} selesai. ${result.damagedQuantity} unit rusak dicatat tanpa movement stok tambahan.`;
  } catch (error) {
    kind = "error";
    text = message(error);
  }

  revalidatePath("/returns");
  revalidatePath("/products");
  revalidatePath("/");
  destination(form, kind, text);
}

export async function markReturnLostAction(form: FormData) {
  const session = await requireAdminSession();
  let kind: "success" | "error" = "success";
  let text = "Barang hilang berhasil dicatat.";

  try {
    confirmed(form);
    const returnId = uuid(form, "returnId");
    const returnRef = required(form, "returnRef");
    const eventRef = required(form, "lostEventRef");
    const selected = form
      .getAll("lostItemId")
      .filter((value): value is string => typeof value === "string");

    if (!selected.length) {
      throw new Error("Pilih minimal satu item yang hilang.");
    }

    const seen = new Set<string>();
    const lines = selected.map((returnItemId, index) => {
      if (!UUID.test(returnItemId) || seen.has(returnItemId)) {
        throw new Error("Item hilang duplikat atau tidak valid.");
      }

      seen.add(returnItemId);

      return {
        returnItemId,
        quantity: positive(
          required(form, `lostQuantity_${returnItemId}`),
          "Quantity hilang",
        ),
        sourceLineRef: `RETURN-LOST-${index + 1}`,
      };
    });

    const result = await markReturnLost({
      organizationId: session.profile.organization_id,
      idempotencyKey: `returns:lost:${eventRef}`,
      returnRef,
      eventRef,
      occurredAt: occurredAt(form),
      lines,
      note: String(form.get("note") ?? "").trim() || null,
      metadata: {
        source: "returns-admin",
        version: 2,
        actorUserId: session.user.id,
        returnId,
      },
    });

    text = `${result.totalQuantity} unit ditandai hilang. Tidak ada movement stok tambahan.`;
  } catch (error) {
    kind = "error";
    text = message(error);
  }

  revalidatePath("/returns");
  revalidatePath("/notifications");
  revalidatePath("/");
  destination(form, kind, text);
}
