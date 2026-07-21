export const MARKETPLACE_CANCELLATION_PHASE_CODES = [
  "PRE_SHIPMENT",
  "POST_SHIPMENT",
] as const;

export const MARKETPLACE_CANCELLATION_CHANNEL_CODES = [
  "SHOPEE",
  "TIKTOK_SHOP",
] as const;

export type MarketplaceCancellationPhaseCode =
  (typeof MARKETPLACE_CANCELLATION_PHASE_CODES)[number];

export type MarketplaceCancellationChannelCode =
  (typeof MARKETPLACE_CANCELLATION_CHANNEL_CODES)[number];

export type MarketplaceCancellationDraftLine = {
  productId: string;
  orderItemRef: string;
  phaseCode: MarketplaceCancellationPhaseCode;
  quantity: number;
  sourceLineRef: string;
};

export type MarketplaceCancellationDraft = {
  channelCode: MarketplaceCancellationChannelCode;
  eventRef: string;
  orderRef: string;
  occurredAt: string;
  sourceStatus: string;
  lines: MarketplaceCancellationDraftLine[];
  note: string | null;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LOCAL_DATE_TIME_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;

function requiredString(
  value: unknown,
  code: string,
  maximumLength: number,
) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(code);
  }

  const normalized = value.trim();

  if (normalized.length > maximumLength) {
    throw new Error(`${code}_TOO_LONG`);
  }

  return normalized;
}

function optionalString(
  value: unknown,
  code: string,
  maximumLength: number,
) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value !== "string") {
    throw new Error(code);
  }

  const normalized = value.trim();

  if (!normalized) {
    return null;
  }

  if (normalized.length > maximumLength) {
    throw new Error(`${code}_TOO_LONG`);
  }

  return normalized;
}

export function parseMarketplaceCancellationDraft(
  value: unknown,
): MarketplaceCancellationDraft {
  let parsed = value;

  if (typeof value === "string") {
    try {
      parsed = JSON.parse(value);
    } catch {
      throw new Error("MARKETPLACE_CANCELLATION_DRAFT_INVALID");
    }
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("MARKETPLACE_CANCELLATION_DRAFT_INVALID");
  }

  const record = parsed as Record<string, unknown>;
  const channelCode = requiredString(
    record.channelCode,
    "MARKETPLACE_CANCELLATION_CHANNEL_REQUIRED",
    100,
  ).toUpperCase();

  if (
    !MARKETPLACE_CANCELLATION_CHANNEL_CODES.includes(
      channelCode as MarketplaceCancellationChannelCode,
    )
  ) {
    throw new Error("MARKETPLACE_CANCELLATION_CHANNEL_NOT_ALLOWED");
  }

  const eventRef = requiredString(
    record.eventRef,
    "MARKETPLACE_CANCELLATION_EVENT_REF_REQUIRED",
    200,
  );
  const orderRef = requiredString(
    record.orderRef,
    "MARKETPLACE_CANCELLATION_ORDER_REF_REQUIRED",
    200,
  );
  const occurredAt = requiredString(
    record.occurredAt,
    "MARKETPLACE_CANCELLATION_OCCURRED_AT_REQUIRED",
    16,
  );

  if (
    !LOCAL_DATE_TIME_PATTERN.test(occurredAt) ||
    Number.isNaN(new Date(`${occurredAt}:00+07:00`).getTime())
  ) {
    throw new Error("MARKETPLACE_CANCELLATION_OCCURRED_AT_INVALID");
  }

  const sourceStatus = requiredString(
    record.sourceStatus,
    "MARKETPLACE_CANCELLATION_SOURCE_STATUS_REQUIRED",
    100,
  );

  if (!Array.isArray(record.lines) || record.lines.length === 0) {
    throw new Error("MARKETPLACE_CANCELLATION_LINES_REQUIRED");
  }

  if (record.lines.length > 200) {
    throw new Error("MARKETPLACE_CANCELLATION_LINES_LIMIT_EXCEEDED");
  }

  const lines = record.lines.map((line, index) => {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      throw new Error("MARKETPLACE_CANCELLATION_LINE_INVALID");
    }

    const lineRecord = line as Record<string, unknown>;
    const productId = requiredString(
      lineRecord.productId,
      "MARKETPLACE_CANCELLATION_PRODUCT_REQUIRED",
      36,
    );

    if (!UUID_PATTERN.test(productId)) {
      throw new Error("MARKETPLACE_CANCELLATION_PRODUCT_INVALID");
    }

    const orderItemRef = requiredString(
      lineRecord.orderItemRef,
      "MARKETPLACE_CANCELLATION_ORDER_ITEM_REF_REQUIRED",
      100,
    );
    const phaseCode = requiredString(
      lineRecord.phaseCode,
      "MARKETPLACE_CANCELLATION_PHASE_REQUIRED",
      100,
    ).toUpperCase();

    if (
      !MARKETPLACE_CANCELLATION_PHASE_CODES.includes(
        phaseCode as MarketplaceCancellationPhaseCode,
      )
    ) {
      throw new Error("MARKETPLACE_CANCELLATION_PHASE_INVALID");
    }

    const quantity = Number(lineRecord.quantity);

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0 ||
      quantity > 999_999_999
    ) {
      throw new Error("MARKETPLACE_CANCELLATION_QUANTITY_INVALID");
    }

    const sourceLineRef = requiredString(
      lineRecord.sourceLineRef ?? `UI-${index + 1}`,
      "MARKETPLACE_CANCELLATION_SOURCE_LINE_REQUIRED",
      100,
    );

    return {
      productId,
      orderItemRef,
      phaseCode: phaseCode as MarketplaceCancellationPhaseCode,
      quantity,
      sourceLineRef,
    };
  });

  const itemPhaseKeys = lines.map(
    (line) => `${line.orderItemRef}\u0000${line.phaseCode}`,
  );

  if (new Set(itemPhaseKeys).size !== itemPhaseKeys.length) {
    throw new Error("MARKETPLACE_CANCELLATION_DUPLICATE_ITEM_PHASE");
  }

  const sourceLineRefs = lines.map((line) => line.sourceLineRef);

  if (new Set(sourceLineRefs).size !== sourceLineRefs.length) {
    throw new Error("MARKETPLACE_CANCELLATION_DUPLICATE_SOURCE_LINE");
  }

  return {
    channelCode: channelCode as MarketplaceCancellationChannelCode,
    eventRef,
    orderRef,
    occurredAt,
    sourceStatus,
    lines,
    note: optionalString(
      record.note,
      "MARKETPLACE_CANCELLATION_NOTE_INVALID",
      2000,
    ),
  };
}

export function serializeMarketplaceCancellationDraft(
  draft: MarketplaceCancellationDraft,
) {
  return JSON.stringify(draft);
}

export function marketplaceCancellationOccurredAt(
  draft: MarketplaceCancellationDraft,
) {
  return `${draft.occurredAt}:00+07:00`;
}

export function marketplaceCancellationHasPostShipment(
  draft: MarketplaceCancellationDraft,
) {
  return draft.lines.some((line) => line.phaseCode === "POST_SHIPMENT");
}

export function marketplaceCancellationErrorMessage(error: unknown) {
  const raw =
    error instanceof Error
      ? error.message
      : "Terjadi kesalahan yang tidak diketahui.";

  const messages: Record<string, string> = {
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    ORGANIZATION_ACCESS_DENIED:
      "Pembatalan tidak dapat diproses untuk organisasi lain.",
    ORGANIZATION_NOT_FOUND:
      "Organisasi aktif tidak ditemukan.",
    MARKETPLACE_CANCELLATION_DRAFT_INVALID:
      "Data draft pembatalan tidak dapat dibaca. Isi ulang formulir.",
    MARKETPLACE_CANCELLATION_CHANNEL_REQUIRED:
      "Channel marketplace wajib dipilih.",
    MARKETPLACE_CANCELLATION_CHANNEL_REQUIRED_TOO_LONG:
      "Kode channel marketplace terlalu panjang.",
    MARKETPLACE_CANCELLATION_CHANNEL_NOT_ALLOWED:
      "Channel tersebut bukan marketplace aktif yang didukung.",
    MARKETPLACE_CANCELLATION_EVENT_REF_REQUIRED:
      "Referensi event pembatalan wajib diisi.",
    MARKETPLACE_CANCELLATION_EVENT_REF_REQUIRED_TOO_LONG:
      "Referensi event pembatalan maksimal 200 karakter.",
    MARKETPLACE_CANCELLATION_EVENT_REF_TOO_LONG:
      "Referensi event pembatalan maksimal 200 karakter.",
    MARKETPLACE_CANCELLATION_EVENT_ALREADY_APPLIED:
      "Event pembatalan tersebut sudah pernah diposting.",
    MARKETPLACE_CANCELLATION_ORDER_REF_REQUIRED:
      "Referensi order marketplace wajib diisi.",
    MARKETPLACE_CANCELLATION_ORDER_REF_REQUIRED_TOO_LONG:
      "Referensi order marketplace maksimal 200 karakter.",
    MARKETPLACE_CANCELLATION_ORDER_REF_TOO_LONG:
      "Referensi order marketplace maksimal 200 karakter.",
    MARKETPLACE_CANCELLATION_ORDER_NOT_FOUND:
      "Order marketplace tidak ditemukan.",
    MARKETPLACE_CANCELLATION_OCCURRED_AT_REQUIRED:
      "Waktu pembatalan wajib diisi.",
    MARKETPLACE_CANCELLATION_OCCURRED_AT_REQUIRED_TOO_LONG:
      "Waktu pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_OCCURRED_AT_INVALID:
      "Waktu pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_SOURCE_STATUS_REQUIRED:
      "Status sumber marketplace wajib diisi.",
    MARKETPLACE_CANCELLATION_SOURCE_STATUS_REQUIRED_TOO_LONG:
      "Status sumber marketplace maksimal 100 karakter.",
    MARKETPLACE_CANCELLATION_SOURCE_STATUS_TOO_LONG:
      "Status sumber marketplace maksimal 100 karakter.",
    MARKETPLACE_CANCELLATION_LINES_REQUIRED:
      "Minimal satu item pembatalan wajib ditambahkan.",
    MARKETPLACE_CANCELLATION_LINES_MUST_BE_ARRAY:
      "Daftar item pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_LINES_LIMIT_EXCEEDED:
      "Jumlah item pembatalan melebihi batas.",
    MARKETPLACE_CANCELLATION_LINE_INVALID:
      "Salah satu item pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_PRODUCT_REQUIRED:
      "Produk wajib tersedia pada setiap item pembatalan.",
    MARKETPLACE_CANCELLATION_PRODUCT_INVALID:
      "Identitas produk pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_ORDER_ITEM_REF_REQUIRED:
      "Referensi item order wajib tersedia.",
    MARKETPLACE_CANCELLATION_PHASE_REQUIRED:
      "Fase pembatalan wajib ditentukan.",
    MARKETPLACE_CANCELLATION_PHASE_INVALID:
      "Fase pembatalan harus sebelum atau sesudah shipment.",
    MARKETPLACE_CANCELLATION_QUANTITY_INVALID:
      "Quantity pembatalan harus berupa bilangan bulat positif.",
    MARKETPLACE_CANCELLATION_SOURCE_LINE_REQUIRED:
      "Referensi baris pembatalan wajib tersedia.",
    MARKETPLACE_CANCELLATION_DUPLICATE_ITEM_PHASE:
      "Satu item dan fase pembatalan hanya boleh muncul sekali.",
    MARKETPLACE_CANCELLATION_DUPLICATE_SOURCE_LINE:
      "Referensi baris pembatalan tidak boleh duplikat.",
    MARKETPLACE_CANCELLATION_ORDER_ITEM_NOT_FOUND:
      "Item order marketplace tidak ditemukan.",
    MARKETPLACE_CANCELLATION_BEFORE_ORDER:
      "Waktu pembatalan tidak boleh lebih awal dari waktu order.",
    MARKETPLACE_CANCELLATION_BEFORE_SHIPMENT:
      "Pembatalan sesudah shipment tidak boleh lebih awal dari shipment asal.",
    MARKETPLACE_CANCELLATION_EXCEEDS_OPEN_RESERVATION:
      "Quantity pembatalan melebihi reservasi yang masih terbuka.",
    MARKETPLACE_CANCELLATION_EXCEEDS_SHIPPED_REMAINING:
      "Quantity pembatalan melebihi shipment yang masih dapat dibalik.",
    MARKETPLACE_CANCELLATION_RETURN_CONFLICT:
      "Item sudah memiliki proses retur sehingga shipment tidak boleh dibalik melalui pembatalan.",
    MARKETPLACE_CANCELLATION_POST_NOTE_REQUIRED:
      "Pembatalan sesudah shipment wajib memiliki alasan audit.",
    MARKETPLACE_CANCELLATION_RESERVATION_PROJECTION_MISMATCH:
      "Projection reserved tidak cukup untuk pelepasan reservasi.",
    MARKETPLACE_CANCELLATION_RESERVATION_PROJECTION_DRIFT:
      "Projection reservasi tidak konsisten dengan data reservasi order.",
    MARKETPLACE_CANCELLATION_PRODUCT_POSITION_NOT_FOUND:
      "Posisi stok produk tidak ditemukan.",
    MARKETPLACE_CANCELLATION_PRODUCT_PROJECTION_DRIFT:
      "Projection produk tidak sama dengan ledger.",
    MARKETPLACE_CANCELLATION_BATCH_PROJECTION_DRIFT:
      "Projection batch shipment tidak sama dengan ledger.",
    MARKETPLACE_CANCELLATION_ALLOCATION_BASIS_INSUFFICIENT:
      "Alokasi shipment yang dapat dibalik tidak mencukupi.",
    MARKETPLACE_CANCELLATION_PREVIEW_BLOCKED:
      "Pembatalan tidak dapat diposting karena preview masih memiliki blocker.",
    MARKETPLACE_CANCELLATION_PREVIEW_HASH_INVALID:
      "Basis preview pembatalan tidak valid. Tinjau ulang draft.",
    STALE_MARKETPLACE_CANCELLATION_PREVIEW:
      "Kondisi order, reservasi, return, atau stok berubah setelah preview. Tinjau preview terbaru.",
    MARKETPLACE_CANCELLATION_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang untuk pembatalan sesudah shipment.",
    MARKETPLACE_CANCELLATION_RESERVATION_STALE:
      "Reservasi berubah saat pembatalan diposting. Tinjau ulang preview.",
    MARKETPLACE_CANCELLATION_ORIGINAL_TRANSACTION_NOT_FOUND:
      "Transaksi shipment asal tidak ditemukan.",
    MARKETPLACE_CANCELLATION_ALLOCATION_NOT_FOUND:
      "Alokasi shipment asal tidak ditemukan.",
    MARKETPLACE_CANCELLATION_LINE_NOT_FOUND:
      "Baris pembatalan tidak ditemukan.",
    MARKETPLACE_CANCELLATION_REVERSAL_APPLICATION_NOT_FOUND:
      "Link reversal pembatalan tidak ditemukan.",
    MARKETPLACE_CANCELLATION_APPLICATION_IDENTITY_MISMATCH:
      "Identitas aplikasi pembatalan tidak cocok dengan item asal.",
    MARKETPLACE_CANCELLATION_APPLICATION_PHASE_MISMATCH:
      "Dampak pembatalan tidak cocok dengan fase item.",
    MARKETPLACE_CANCELLATION_APPLICATION_OVER_APPLIED:
      "Quantity pembatalan melebihi quantity yang tersedia.",
    MARKETPLACE_CANCELLATION_REVERSAL_LINK_MISMATCH:
      "Link ledger reversal pembatalan tidak konsisten.",
    REVERSAL_REASON_NOT_CONFIGURED:
      "Alasan pergerakan REVERSAL belum dikonfigurasi.",
    MARKETPLACE_CANCELLATION_METADATA_MUST_BE_OBJECT:
      "Metadata pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_NOTE_INVALID:
      "Catatan pembatalan tidak valid.",
    MARKETPLACE_CANCELLATION_NOTE_INVALID_TOO_LONG:
      "Catatan pembatalan maksimal 2.000 karakter.",
    MARKETPLACE_CANCELLATION_NOTE_TOO_LONG:
      "Catatan pembatalan maksimal 2.000 karakter.",
    IDEMPOTENCY_KEY_REQUIRED:
      "Referensi proses pembatalan tidak tersedia. Muat ulang preview.",
    IDEMPOTENCY_KEY_TOO_LONG:
      "Referensi proses pembatalan terlalu panjang.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi proses sudah digunakan untuk payload berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Pembatalan yang sama masih diproses.",
    IDEMPOTENCY_COMMAND_FAILED:
      "Percobaan pembatalan sebelumnya gagal dan tidak dapat dipakai ulang.",
  };

  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}
