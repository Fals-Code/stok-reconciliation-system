export const MANUAL_OUTBOUND_REASON_CODES = [
  "OFFLINE_SALE",
  "BONUS",
  "PROMO",
  "SAMPLE",
] as const;

export type ManualOutboundReasonCode =
  (typeof MANUAL_OUTBOUND_REASON_CODES)[number];

export type ManualOutboundDraftLine = {
  productId: string;
  quantity: number;
  sourceLineRef: string;
};

export type ManualOutboundDraft = {
  sourceRef: string;
  occurredAt: string;
  reasonCode: ManualOutboundReasonCode;
  lines: ManualOutboundDraftLine[];
  note: string | null;
  reference: string | null;
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

export function parseManualOutboundDraft(value: unknown): ManualOutboundDraft {
  let parsed = value;

  if (typeof value === "string") {
    try {
      parsed = JSON.parse(value);
    } catch {
      throw new Error("MANUAL_OUTBOUND_DRAFT_INVALID");
    }
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("MANUAL_OUTBOUND_DRAFT_INVALID");
  }

  const record = parsed as Record<string, unknown>;
  const sourceRef = requiredString(
    record.sourceRef,
    "OUTBOUND_SOURCE_REQUIRED",
    200,
  );
  const occurredAt = requiredString(
    record.occurredAt,
    "OUTBOUND_OCCURRED_AT_REQUIRED",
    16,
  );

  if (
    !LOCAL_DATE_TIME_PATTERN.test(occurredAt) ||
    Number.isNaN(new Date(`${occurredAt}:00+07:00`).getTime())
  ) {
    throw new Error("OUTBOUND_OCCURRED_AT_INVALID");
  }

  const reasonCode = requiredString(
    record.reasonCode,
    "OUTBOUND_REASON_REQUIRED",
    100,
  ).toUpperCase();

  if (
    !MANUAL_OUTBOUND_REASON_CODES.includes(
      reasonCode as ManualOutboundReasonCode,
    )
  ) {
    throw new Error("OUTBOUND_REASON_NOT_ALLOWED");
  }

  if (!Array.isArray(record.lines) || record.lines.length === 0) {
    throw new Error("OUTBOUND_LINES_REQUIRED");
  }

  if (record.lines.length > 200) {
    throw new Error("OUTBOUND_LINES_LIMIT_EXCEEDED");
  }

  const lines = record.lines.map((line, index) => {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      throw new Error("OUTBOUND_LINE_INVALID");
    }

    const lineRecord = line as Record<string, unknown>;
    const productId = requiredString(
      lineRecord.productId,
      "OUTBOUND_PRODUCT_REQUIRED",
      36,
    );

    if (!UUID_PATTERN.test(productId)) {
      throw new Error("OUTBOUND_PRODUCT_INVALID");
    }

    const quantity = Number(lineRecord.quantity);

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0 ||
      quantity > 999_999_999
    ) {
      throw new Error("OUTBOUND_QUANTITY_INVALID");
    }

    const sourceLineRef = requiredString(
      lineRecord.sourceLineRef ?? `UI-${index + 1}`,
      "OUTBOUND_SOURCE_LINE_REQUIRED",
      100,
    );

    return {
      productId,
      quantity,
      sourceLineRef,
    };
  });

  const productIds = lines.map((line) => line.productId.toLowerCase());
  if (new Set(productIds).size !== productIds.length) {
    throw new Error("OUTBOUND_DUPLICATE_PRODUCT_LINE");
  }

  const sourceLineRefs = lines.map((line) => line.sourceLineRef);
  if (new Set(sourceLineRefs).size !== sourceLineRefs.length) {
    throw new Error("OUTBOUND_DUPLICATE_SOURCE_LINE");
  }

  return {
    sourceRef,
    occurredAt,
    reasonCode: reasonCode as ManualOutboundReasonCode,
    lines,
    note: optionalString(record.note, "OUTBOUND_NOTE_INVALID", 2000),
    reference: optionalString(
      record.reference,
      "OUTBOUND_REFERENCE_INVALID",
      200,
    ),
  };
}

export function serializeManualOutboundDraft(draft: ManualOutboundDraft) {
  return JSON.stringify(draft);
}

export function manualOutboundOccurredAt(draft: ManualOutboundDraft) {
  return `${draft.occurredAt}:00+07:00`;
}

export function manualOutboundErrorMessage(error: unknown) {
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
      "Barang keluar tidak dapat diproses untuk organisasi lain.",
    MANUAL_OUTBOUND_DRAFT_INVALID:
      "Data draft barang keluar tidak dapat dibaca. Isi ulang formulir.",
    OUTBOUND_SOURCE_REQUIRED:
      "Referensi barang keluar wajib diisi.",
    OUTBOUND_SOURCE_REQUIRED_TOO_LONG:
      "Referensi barang keluar maksimal 200 karakter.",
    OUTBOUND_SOURCE_TOO_LONG:
      "Referensi barang keluar maksimal 200 karakter.",
    OUTBOUND_SOURCE_ALREADY_POSTED:
      "Referensi barang keluar ini sudah pernah diposting.",
    OUTBOUND_OCCURRED_AT_REQUIRED:
      "Waktu barang keluar wajib diisi.",
    OUTBOUND_OCCURRED_AT_INVALID:
      "Waktu barang keluar tidak valid.",
    OUTBOUND_REASON_REQUIRED:
      "Alasan barang keluar wajib dipilih.",
    OUTBOUND_REASON_REQUIRED_TOO_LONG:
      "Kode alasan barang keluar terlalu panjang.",
    OUTBOUND_REASON_TOO_LONG:
      "Kode alasan barang keluar terlalu panjang.",
    OUTBOUND_REASON_NOT_ALLOWED:
      "Alasan barang keluar tidak diizinkan untuk alur FEFO umum.",
    OUTBOUND_LINES_REQUIRED:
      "Minimal satu produk wajib ditambahkan.",
    OUTBOUND_LINES_LIMIT_EXCEEDED:
      "Jumlah baris produk melebihi batas.",
    OUTBOUND_LINE_INVALID:
      "Salah satu baris produk tidak valid.",
    OUTBOUND_PRODUCT_REQUIRED:
      "Produk wajib dipilih pada setiap baris.",
    OUTBOUND_PRODUCT_INVALID:
      "Identitas produk tidak valid.",
    OUTBOUND_PRODUCT_NOT_FOUND:
      "Produk tidak ditemukan pada organisasi aktif.",
    OUTBOUND_PRODUCT_INACTIVE:
      "Produk tidak aktif dan tidak dapat dikeluarkan.",
    OUTBOUND_PRODUCT_NOT_BATCH_TRACKED:
      "Produk tidak menggunakan pelacakan batch.",
    OUTBOUND_PRODUCT_NOT_EXPIRY_TRACKED:
      "Produk tidak menggunakan pelacakan kedaluwarsa.",
    OUTBOUND_QUANTITY_INVALID:
      "Quantity harus berupa bilangan bulat positif.",
    OUTBOUND_SOURCE_LINE_REQUIRED:
      "Referensi baris produk tidak tersedia.",
    OUTBOUND_DUPLICATE_PRODUCT_LINE:
      "Satu produk hanya boleh muncul sekali dalam satu draft.",
    OUTBOUND_DUPLICATE_SOURCE_LINE:
      "Referensi baris produk tidak boleh duplikat.",
    OUTBOUND_NOTE_INVALID:
      "Catatan barang keluar tidak valid.",
    OUTBOUND_NOTE_INVALID_TOO_LONG:
      "Catatan maksimal 2.000 karakter.",
    OUTBOUND_NOTE_TOO_LONG:
      "Catatan maksimal 2.000 karakter.",
    OUTBOUND_NOTE_REQUIRED:
      "Catatan wajib diisi untuk alasan barang keluar ini.",
    OUTBOUND_REFERENCE_INVALID:
      "Referensi kegiatan atau penerima tidak valid.",
    OUTBOUND_REFERENCE_INVALID_TOO_LONG:
      "Referensi kegiatan atau penerima maksimal 200 karakter.",
    OUTBOUND_REFERENCE_TOO_LONG:
      "Referensi kegiatan atau penerima maksimal 200 karakter.",
    OUTBOUND_REASON_REFERENCE_REQUIRED:
      "Bonus, promo, atau sample wajib memiliki referensi kegiatan, persetujuan, penerima, atau pesanan.",
    OUTBOUND_METADATA_MUST_BE_OBJECT:
      "Metadata barang keluar tidak valid.",
    INSUFFICIENT_AVAILABLE_STOCK:
      "Stok tersedia setelah reservasi tidak mencukupi.",
    INSUFFICIENT_FEFO_STOCK:
      "Stok batch yang memenuhi FEFO dan batas kedaluwarsa tidak mencukupi.",
    EXPIRY_SAFETY_BUFFER_INVALID:
      "Konfigurasi batas aman kedaluwarsa tidak valid.",
    OUTBOUND_CHANNEL_NOT_CONFIGURED:
      "Channel MANUAL belum dikonfigurasi.",
    MANUAL_OUTBOUND_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang.",
    MANUAL_OUTBOUND_PREVIEW_HASH_INVALID:
      "Basis preview tidak valid. Tinjau ulang draft.",
    MANUAL_OUTBOUND_PREVIEW_BLOCKED:
      "Barang keluar tidak dapat diposting karena preview masih memiliki blocker.",
    STALE_MANUAL_OUTBOUND_PREVIEW:
      "Posisi stok berubah setelah preview dibuat. Tinjau preview terbaru sebelum mengonfirmasi ulang.",
    IDEMPOTENCY_KEY_REQUIRED:
      "Referensi proses barang keluar tidak tersedia. Muat ulang preview.",
    IDEMPOTENCY_KEY_TOO_LONG:
      "Referensi proses barang keluar terlalu panjang.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi proses sudah digunakan untuk payload berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Barang keluar yang sama masih diproses.",
    IDEMPOTENCY_COMMAND_FAILED:
      "Percobaan barang keluar sebelumnya gagal dan tidak dapat dipakai ulang.",
  };

  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}
