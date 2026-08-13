"use server";

import {
  revalidatePath,
} from "next/cache";
import {
  redirect,
} from "next/navigation";

import {
  requireAdminSession,
} from "@/lib/auth";
import {
  reserveMarketplaceListingEvent,
  shipMarketplaceListingEvent,
} from "@/lib/supabase-rest";

function required(
  formData: FormData,
  key: string,
) {
  const value = formData.get(key);

  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function positiveInteger(
  formData: FormData,
  key: string,
) {
  const value = Number(
    required(formData, key),
  );

  if (
    !Number.isSafeInteger(value) ||
    value <= 0
  ) {
    throw new Error(
      `${key} harus berupa bilangan bulat positif.`,
    );
  }

  return value;
}

function jakartaTimestamp(
  raw: string,
) {
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(
      raw,
    )
  ) {
    throw new Error(
      "Waktu transaksi tidak valid.",
    );
  }

  return `${raw}:00+07:00`;
}

function errorMessage(
  error: unknown,
) {
  return error instanceof Error
    ? error.message
    : "Terjadi kesalahan yang tidak diketahui.";
}

function marketplaceErrorMessage(
  error: unknown,
) {
  const raw = errorMessage(error);

  const messages: Record<
    string,
    string
  > = {
    INSUFFICIENT_AVAILABLE_STOCK:
      "Stok available tidak mencukupi untuk reservasi tersebut.",
    INSUFFICIENT_FEFO_STOCK:
      "Stok batch yang memenuhi aturan FEFO tidak mencukupi untuk shipment.",
    MARKETPLACE_ORDER_ALREADY_EXISTS:
      "Order marketplace tersebut sudah pernah dibuat.",
    MARKETPLACE_EVENT_ALREADY_APPLIED:
      "Event marketplace tersebut sudah pernah diterapkan.",
    MARKETPLACE_ORDER_NOT_FOUND:
      "Order marketplace tidak ditemukan.",
    MARKETPLACE_ORDER_ITEM_NOT_FOUND:
      "Item reservasi pada order marketplace tidak ditemukan.",
    MARKETPLACE_RESERVATION_EXCEEDED:
      "Quantity melebihi sisa reservasi yang masih terbuka.",
    MARKETPLACE_CHANNEL_NOT_ALLOWED:
      "Channel tersebut bukan marketplace aktif.",
    MARKETPLACE_LISTING_NOT_FOUND:
      "Kode listing marketplace belum memiliki mapping aktif.",
    MARKETPLACE_LISTING_ARCHIVED:
      "Listing marketplace sudah diarsipkan.",
    MARKETPLACE_LISTING_MAPPING_NOT_FOUND:
      "Mapping produk untuk waktu event tidak ditemukan.",
    MARKETPLACE_LISTING_MAPPING_AMBIGUOUS:
      "Mapping listing bertumpang tindih dan harus diperbaiki.",
    MARKETPLACE_BUNDLE_RECIPE_NOT_FOUND:
      "Resep bundle aktif untuk waktu event tidak ditemukan.",
    MARKETPLACE_BUNDLE_RECIPE_AMBIGUOUS:
      "Versi resep bundle bertumpang tindih dan harus diperbaiki.",
    MARKETPLACE_LISTING_PRODUCT_INACTIVE:
      "Produk pada mapping listing sedang tidak aktif.",
    MARKETPLACE_BUNDLE_COMPONENT_INACTIVE:
      "Salah satu produk komponen bundle sedang tidak aktif.",
    MARKETPLACE_SOURCE_COMPONENT_NOT_FOUND:
      "Komponen order dari listing tersebut tidak ditemukan.",
    MARKETPLACE_SOURCE_COMPONENT_QUANTITY_EXCEEDED:
      "Quantity melebihi jumlah komponen hasil ekspansi order.",
    MARKETPLACE_SOURCE_STATUS_NOT_SHIPPABLE:
      "Status sumber belum memenuhi waktu pengurangan stok channel.",
    MARKETPLACE_RECEIVED_BEFORE_OCCURRED:
      "Waktu penerimaan event tidak boleh mendahului waktu kejadian.",
    RESERVATION_PROJECTION_MISMATCH:
      "Proyeksi reserved stock tidak konsisten dengan reservasi order.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi event sudah dipakai untuk payload yang berbeda.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched =
    Object.entries(messages).find(
      ([code]) => raw.includes(code),
    );

  return matched
    ? matched[1]
    : raw;
}

type MarketplaceChannelCode =
  | "SHOPEE"
  | "TIKTOK_SHOP";

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

function parsedObject(
  formData: FormData,
  key: string,
  message: string,
) {
  const raw = required(
    formData,
    key,
  );

  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(message);
  }

  if (
    !parsed ||
    typeof parsed !== "object"
  ) {
    throw new Error(message);
  }

  return parsed as Record<
    string,
    unknown
  >;
}

function marketplaceListingSelection(
  formData: FormData,
): MarketplaceListingSelection {
  const value = parsedObject(
    formData,
    "marketplaceListingSelection",
    "Pilihan listing marketplace tidak valid.",
  );

  const channelCode = String(
    value.channelCode ?? "",
  )
    .trim()
    .toUpperCase();

  const listingType = String(
    value.listingType ?? "",
  )
    .trim()
    .toUpperCase();

  const externalListingCode =
    String(
      value.externalListingCode ?? "",
    ).trim();

  const listingName = String(
    value.listingName ?? "",
  ).trim();

  if (
    !new Set([
      "SHOPEE",
      "TIKTOK_SHOP",
    ]).has(channelCode)
  ) {
    throw new Error(
      "Channel listing marketplace tidak valid.",
    );
  }

  if (
    !new Set([
      "SINGLE",
      "BUNDLE",
    ]).has(listingType)
  ) {
    throw new Error(
      "Jenis listing marketplace tidak valid.",
    );
  }

  if (
    !externalListingCode ||
    !listingName
  ) {
    throw new Error(
      "Pilihan listing marketplace tidak lengkap.",
    );
  }

  return {
    channelCode:
      channelCode as MarketplaceChannelCode,
    externalListingCode,
    listingName,
    listingType:
      listingType as
        | "SINGLE"
        | "BUNDLE",
  };
}

function marketplaceSelection(
  formData: FormData,
): MarketplaceSelection {
  const value = parsedObject(
    formData,
    "marketplaceSelection",
    "Pilihan komponen marketplace tidak valid.",
  );

  const channelCode = String(
    value.channelCode ?? "",
  )
    .trim()
    .toUpperCase();

  const orderRef = String(
    value.orderRef ?? "",
  ).trim();

  const orderSourceLineRef =
    String(
      value.orderSourceLineRef ?? "",
    ).trim();

  const componentNo =
    Number(value.componentNo);

  if (
    !new Set([
      "SHOPEE",
      "TIKTOK_SHOP",
    ]).has(channelCode)
  ) {
    throw new Error(
      "Channel komponen marketplace tidak valid.",
    );
  }

  if (
    !orderRef ||
    !orderSourceLineRef
  ) {
    throw new Error(
      "Pilihan komponen marketplace tidak lengkap.",
    );
  }

  if (
    !Number.isSafeInteger(
      componentNo,
    ) ||
    componentNo <= 0
  ) {
    throw new Error(
      "Nomor komponen marketplace tidak valid.",
    );
  }

  return {
    channelCode:
      channelCode as MarketplaceChannelCode,
    orderRef,
    orderSourceLineRef,
    componentNo,
  };
}

function resultRedirect(
  kind: "success" | "error",
  message: string,
) {
  const params =
    new URLSearchParams({
      [kind]: message,
    });

  redirect(
    `/marketplace/simulator?${params.toString()}#simulator`,
  );
}

export async function reserveMarketplaceOrderAction(
  formData: FormData,
) {
  const session =
    await requireAdminSession();

  let message: string;
  let kind:
    | "success"
    | "error" = "success";

  try {
    const selection =
      marketplaceListingSelection(
        formData,
      );

    const orderRef =
      required(
        formData,
        "orderRef",
      );

    const eventRef =
      required(
        formData,
        "eventRef",
      );

    const occurredAt =
      jakartaTimestamp(
        required(
          formData,
          "occurredAt",
        ),
      );

    const sourceLineRef =
      required(
        formData,
        "sourceLineRef",
      );

    const listingQuantity =
      positiveInteger(
        formData,
        "listingQuantity",
      );

    const note =
      String(
        formData.get("note") ?? "",
      ).trim() || null;

    const sourceStatus =
      "READY_TO_SHIP";

    const result =
      await reserveMarketplaceListingEvent(
        {
          organizationId:
            session.profile
              .organization_id,

          idempotencyKey:
            `marketplace-listing-reserve:${selection.channelCode}:${eventRef}`,

          channelCode:
            selection.channelCode,
          eventRef,
          orderRef,
          sourceStatus,
          occurredAt,
          receivedAt: occurredAt,

          lines: [
            {
              sourceLineRef,
              externalListingCode:
                selection.externalListingCode,
              listingQuantity,
              sourceTitle:
                selection.listingName,
              sourceSku:
                selection.externalListingCode,
              sourceStatus,
              rawLinePayload: {
                source:
                  "marketplace-listing-simulator",
                sourceLineRef,
              },
            },
          ],

          note,

          rawPayload: {
            channelCode:
              selection.channelCode,
            eventRef,
            orderRef,
            sourceStatus,
            externalListingCode:
              selection.externalListingCode,
            listingQuantity,
          },

          metadata: {
            source:
              "marketplace-listing-simulator",
            version: 1,
            actorUserId:
              session.user.id,
          },

          schemaVersion: 1,
        },
      );

    const canonicalLineCount =
      Number(
        result.canonicalLineCount ?? 0,
      );

    const totalUnitQuantity =
      Number(
        result.totalUnitQuantity ??
          result.totalQuantity ??
          0,
      );

    message =
      `${result.orderRef} menormalisasi ${selection.externalListingCode} ` +
      `menjadi ${canonicalLineCount} komponen dan mereservasi ` +
      `${totalUnitQuantity} unit tanpa mengubah stok fisik.`;

    revalidatePath("/");
    revalidatePath("/marketplace");
    revalidatePath(
      "/marketplace/simulator",
    );
  } catch (error) {
    kind = "error";
    message =
      marketplaceErrorMessage(
        error,
      );
  }

  resultRedirect(
    kind,
    message,
  );
}

export async function advanceMarketplaceOrderAction(
  formData: FormData,
) {
  const session =
    await requireAdminSession();

  let message: string;
  let kind:
    | "success"
    | "error" = "success";

  try {
    const selection =
      marketplaceSelection(
        formData,
      );

    const eventRef =
      required(
        formData,
        "eventRef",
      );

    const occurredAt =
      jakartaTimestamp(
        required(
          formData,
          "occurredAt",
        ),
      );

    const quantity =
      positiveInteger(
        formData,
        "quantity",
      );

    const note =
      String(
        formData.get("note") ?? "",
      ).trim() || null;

    const sourceStatus =
      selection.channelCode ===
      "SHOPEE"
        ? "SHIPPED"
        : "IN_TRANSIT";

    const result =
      await shipMarketplaceListingEvent(
        {
          organizationId:
            session.profile
              .organization_id,

          idempotencyKey:
            `marketplace-listing-ship:${selection.channelCode}:${eventRef}`,

          channelCode:
            selection.channelCode,
          eventRef,
          orderRef:
            selection.orderRef,
          sourceStatus,
          occurredAt,
          receivedAt: occurredAt,

          lines: [
            {
              orderSourceLineRef:
                selection.orderSourceLineRef,
              componentNo:
                selection.componentNo,
              quantity,
            },
          ],

          note,

          rawPayload: {
            channelCode:
              selection.channelCode,
            eventRef,
            orderRef:
              selection.orderRef,
            sourceStatus,
            orderSourceLineRef:
              selection.orderSourceLineRef,
            componentNo:
              selection.componentNo,
            quantity,
          },

          metadata: {
            source:
              "marketplace-listing-simulator",
            version: 1,
            actorUserId:
              session.user.id,
          },

          schemaVersion: 1,
        },
      );

    message =
      `${result.transactionNo ?? result.orderRef} mengirim ` +
      `${Number(result.totalQuantity ?? 0)} unit melalui ` +
      `${Number(result.allocationCount ?? 0)} alokasi batch FEFO.`;

    revalidatePath("/");
    revalidatePath("/marketplace");
    revalidatePath(
      "/marketplace/simulator",
    );
  } catch (error) {
    kind = "error";
    message =
      marketplaceErrorMessage(
        error,
      );
  }

  resultRedirect(
    kind,
    message,
  );
}