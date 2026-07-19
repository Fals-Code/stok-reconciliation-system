export const STOCK_DISPOSAL_REASON_CODES = [
  "DAMAGED_DISPOSAL",
  "EXPIRED_DISPOSAL",
] as const;

export const STOCK_DISPOSAL_BUCKET_CODES = [
  "SELLABLE",
  "QUARANTINE",
  "DAMAGED",
] as const;

export type StockDisposalReasonCode =
  (typeof STOCK_DISPOSAL_REASON_CODES)[number];

export type StockDisposalBucketCode =
  (typeof STOCK_DISPOSAL_BUCKET_CODES)[number];

export type StockDisposalDraftLine = {
  productId: string;
  batchId: string;
  sourceBucketCode: StockDisposalBucketCode;
  quantity: number;
  sourceLineRef: string;
};

export type StockDisposalDraft = {
  sourceRef: string;
  occurredAt: string;
  reasonCode: StockDisposalReasonCode;
  lines: StockDisposalDraftLine[];
  referenceText: string;
  note: string;
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

export function parseStockDisposalDraft(value: unknown): StockDisposalDraft {
  let parsed = value;

  if (typeof value === "string") {
    try {
      parsed = JSON.parse(value);
    } catch {
      throw new Error("STOCK_DISPOSAL_DRAFT_INVALID");
    }
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("STOCK_DISPOSAL_DRAFT_INVALID");
  }

  const record = parsed as Record<string, unknown>;
  const sourceRef = requiredString(
    record.sourceRef,
    "DISPOSAL_SOURCE_REQUIRED",
    200,
  );
  const occurredAt = requiredString(
    record.occurredAt,
    "DISPOSAL_OCCURRED_AT_REQUIRED",
    16,
  );

  if (
    !LOCAL_DATE_TIME_PATTERN.test(occurredAt) ||
    Number.isNaN(new Date(`${occurredAt}:00+07:00`).getTime())
  ) {
    throw new Error("DISPOSAL_OCCURRED_AT_INVALID");
  }

  const reasonCode = requiredString(
    record.reasonCode,
    "DISPOSAL_REASON_REQUIRED",
    100,
  ).toUpperCase();

  if (
    !STOCK_DISPOSAL_REASON_CODES.includes(
      reasonCode as StockDisposalReasonCode,
    )
  ) {
    throw new Error("DISPOSAL_REASON_NOT_ALLOWED");
  }

  if (!Array.isArray(record.lines) || record.lines.length === 0) {
    throw new Error("DISPOSAL_LINES_REQUIRED");
  }

  if (record.lines.length > 200) {
    throw new Error("DISPOSAL_LINES_LIMIT_EXCEEDED");
  }

  const lines = record.lines.map((line, index) => {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      throw new Error("DISPOSAL_LINE_INVALID");
    }

    const lineRecord = line as Record<string, unknown>;
    const productId = requiredString(
      lineRecord.productId,
      "DISPOSAL_PRODUCT_REQUIRED",
      36,
    );
    const batchId = requiredString(
      lineRecord.batchId,
      "DISPOSAL_BATCH_REQUIRED",
      36,
    );

    if (!UUID_PATTERN.test(productId)) {
      throw new Error("DISPOSAL_PRODUCT_INVALID");
    }

    if (!UUID_PATTERN.test(batchId)) {
      throw new Error("DISPOSAL_BATCH_INVALID");
    }

    const sourceBucketCode = requiredString(
      lineRecord.sourceBucketCode,
      "DISPOSAL_BUCKET_REQUIRED",
      20,
    ).toUpperCase();

    if (
      !STOCK_DISPOSAL_BUCKET_CODES.includes(
        sourceBucketCode as StockDisposalBucketCode,
      )
    ) {
      throw new Error("DISPOSAL_BUCKET_INVALID");
    }

    const quantity = Number(lineRecord.quantity);

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0 ||
      quantity > 999_999_999
    ) {
      throw new Error("DISPOSAL_QUANTITY_INVALID");
    }

    const sourceLineRef = requiredString(
      lineRecord.sourceLineRef ?? `UI-${index + 1}`,
      "DISPOSAL_SOURCE_LINE_REQUIRED",
      100,
    );

    return {
      productId,
      batchId,
      sourceBucketCode: sourceBucketCode as StockDisposalBucketCode,
      quantity,
      sourceLineRef,
    };
  });

  const identities = lines.map((line) =>
    [
      line.productId.toLowerCase(),
      line.batchId.toLowerCase(),
      line.sourceBucketCode,
    ].join(":"),
  );

  if (new Set(identities).size !== identities.length) {
    throw new Error("DISPOSAL_DUPLICATE_BATCH_BUCKET_LINE");
  }

  const sourceLineRefs = lines.map((line) => line.sourceLineRef);

  if (new Set(sourceLineRefs).size !== sourceLineRefs.length) {
    throw new Error("DISPOSAL_DUPLICATE_SOURCE_LINE");
  }

  return {
    sourceRef,
    occurredAt,
    reasonCode: reasonCode as StockDisposalReasonCode,
    lines,
    referenceText: requiredString(
      record.referenceText,
      "DISPOSAL_REFERENCE_REQUIRED",
      200,
    ),
    note: requiredString(record.note, "DISPOSAL_NOTE_REQUIRED", 2000),
  };
}

export function serializeStockDisposalDraft(draft: StockDisposalDraft) {
  return JSON.stringify(draft);
}

export function stockDisposalOccurredAt(draft: StockDisposalDraft) {
  return `${draft.occurredAt}:00+07:00`;
}

export function stockDisposalErrorMessage(error: unknown) {
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
      "Pemusnahan stok tidak dapat diproses untuk organisasi lain.",
    ORGANIZATION_NOT_FOUND:
      "Organisasi aktif tidak ditemukan.",
    STOCK_DISPOSAL_DRAFT_INVALID:
      "Data draft pemusnahan tidak dapat dibaca. Isi ulang formulir.",
    DISPOSAL_SOURCE_REQUIRED:
      "Referensi pemusnahan wajib diisi.",
    DISPOSAL_SOURCE_REQUIRED_TOO_LONG:
      "Referensi pemusnahan maksimal 200 karakter.",
    DISPOSAL_SOURCE_TOO_LONG:
      "Referensi pemusnahan maksimal 200 karakter.",
    DISPOSAL_SOURCE_ALREADY_POSTED:
      "Referensi pemusnahan ini sudah pernah diposting.",
    DISPOSAL_OCCURRED_AT_REQUIRED:
      "Waktu pemusnahan wajib diisi.",
    DISPOSAL_OCCURRED_AT_INVALID:
      "Waktu pemusnahan tidak valid.",
    DISPOSAL_REASON_REQUIRED:
      "Alasan pemusnahan wajib dipilih.",
    DISPOSAL_REASON_NOT_ALLOWED:
      "Alasan pemusnahan tidak diizinkan.",
    DISPOSAL_REASON_NOT_CONFIGURED:
      "Alasan pemusnahan belum dikonfigurasi.",
    DISPOSAL_LINES_REQUIRED:
      "Minimal satu batch wajib ditambahkan.",
    DISPOSAL_LINES_LIMIT_EXCEEDED:
      "Jumlah baris batch melebihi batas.",
    DISPOSAL_LINES_MUST_BE_ARRAY:
      "Format baris pemusnahan tidak valid.",
    DISPOSAL_LINE_INVALID:
      "Salah satu baris pemusnahan tidak valid.",
    DISPOSAL_PRODUCT_REQUIRED:
      "Produk wajib tersedia pada setiap baris.",
    DISPOSAL_PRODUCT_INVALID:
      "Identitas produk tidak valid.",
    DISPOSAL_PRODUCT_NOT_FOUND:
      "Produk tidak ditemukan pada organisasi aktif.",
    DISPOSAL_PRODUCT_INACTIVE:
      "Produk tidak aktif dan tidak dapat dimusnahkan.",
    DISPOSAL_BATCH_REQUIRED:
      "Batch wajib dipilih pada setiap baris.",
    DISPOSAL_BATCH_INVALID:
      "Identitas batch tidak valid.",
    DISPOSAL_BATCH_NOT_FOUND:
      "Batch tidak ditemukan pada organisasi aktif.",
    DISPOSAL_BATCH_ARCHIVED:
      "Batch berstatus archived harus diselidiki atau diperbaiki sebelum pemusnahan.",
    DISPOSAL_BUCKET_REQUIRED:
      "Bucket sumber wajib dipilih.",
    DISPOSAL_BUCKET_INVALID:
      "Bucket sumber tidak valid.",
    DISPOSAL_QUANTITY_INVALID:
      "Quantity harus berupa bilangan bulat positif.",
    DISPOSAL_SOURCE_LINE_REQUIRED:
      "Referensi baris pemusnahan tidak tersedia.",
    DISPOSAL_DUPLICATE_BATCH_BUCKET_LINE:
      "Kombinasi produk, batch, dan bucket tidak boleh duplikat.",
    DISPOSAL_DUPLICATE_SOURCE_LINE:
      "Referensi baris pemusnahan tidak boleh duplikat.",
    DISPOSAL_REFERENCE_REQUIRED:
      "Referensi bukti atau berita acara wajib diisi.",
    DISPOSAL_REFERENCE_REQUIRED_TOO_LONG:
      "Referensi bukti maksimal 200 karakter.",
    DISPOSAL_REFERENCE_TOO_LONG:
      "Referensi bukti maksimal 200 karakter.",
    DISPOSAL_NOTE_REQUIRED:
      "Catatan pemusnahan wajib diisi.",
    DISPOSAL_NOTE_REQUIRED_TOO_LONG:
      "Catatan pemusnahan maksimal 2.000 karakter.",
    DISPOSAL_NOTE_TOO_LONG:
      "Catatan pemusnahan maksimal 2.000 karakter.",
    DISPOSAL_METADATA_MUST_BE_OBJECT:
      "Metadata pemusnahan tidak valid.",
    INVALID_DAMAGED_DISPOSAL_SOURCE:
      "Pemusnahan barang rusak hanya boleh mengambil bucket DAMAGED.",
    INVALID_EXPIRED_DISPOSAL_SOURCE:
      "Batch belum melewati tanggal kedaluwarsa lokal.",
    DISPOSAL_EXCEEDS_BALANCE:
      "Quantity pemusnahan melebihi saldo bucket batch.",
    DISPOSAL_RESERVED_CONFLICT:
      "Pemusnahan akan membuat reserved melebihi sellable.",
    DISPOSAL_PRODUCT_BUCKET_NEGATIVE:
      "Pemusnahan akan membuat saldo bucket produk negatif.",
    DISPOSAL_PRODUCT_POSITION_CONFLICT:
      "Posisi stok produk berubah atau tidak lagi memenuhi invariant.",
    DISPOSAL_PROJECTION_DRIFT:
      "Projection stok tidak sama dengan ledger. Pemusnahan diblokir.",
    DISPOSAL_CHANNEL_NOT_CONFIGURED:
      "Channel MANUAL belum dikonfigurasi.",
    STOCK_DISPOSAL_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang.",
    STOCK_DISPOSAL_PREVIEW_HASH_INVALID:
      "Basis preview tidak valid. Tinjau ulang draft.",
    STALE_STOCK_DISPOSAL_PREVIEW:
      "Posisi stok atau identitas batch berubah setelah preview dibuat. Tinjau ulang.",
    IDEMPOTENCY_KEY_REQUIRED:
      "Referensi proses pemusnahan tidak tersedia. Muat ulang preview.",
    IDEMPOTENCY_KEY_TOO_LONG:
      "Referensi proses pemusnahan terlalu panjang.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi proses sudah digunakan untuk payload berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Pemusnahan yang sama masih diproses.",
    IDEMPOTENCY_COMMAND_FAILED:
      "Percobaan pemusnahan sebelumnya gagal dan tidak dapat dipakai ulang.",
  };

  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}