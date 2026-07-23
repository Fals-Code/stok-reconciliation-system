export const MARKETPLACE_LISTING_CHANNEL_CODES = [
  "SHOPEE",
  "TIKTOK_SHOP",
] as const;

export const MARKETPLACE_LISTING_TYPE_CODES = ["SINGLE", "BUNDLE"] as const;

export type MarketplaceListingChannelCode =
  (typeof MARKETPLACE_LISTING_CHANNEL_CODES)[number];

export type MarketplaceListingTypeCode =
  (typeof MARKETPLACE_LISTING_TYPE_CODES)[number];

export type MarketplaceListingDraftComponent = {
  productId: string;
  quantity: number;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requiredString(value: unknown, code: string, maximum: number) {
  const resolved = typeof value === "string" ? value.trim() : "";

  if (!resolved) {
    throw new Error(code);
  }

  if (resolved.length > maximum) {
    throw new Error(`${code}_TOO_LONG`);
  }

  return resolved;
}

export function parseMarketplaceListingChannel(
  value: unknown,
): MarketplaceListingChannelCode {
  const resolved = requiredString(
    value,
    "MARKETPLACE_CHANNEL_REQUIRED",
    100,
  ).toUpperCase();

  if (
    !MARKETPLACE_LISTING_CHANNEL_CODES.includes(
      resolved as MarketplaceListingChannelCode,
    )
  ) {
    throw new Error("MARKETPLACE_CHANNEL_NOT_ALLOWED");
  }

  return resolved as MarketplaceListingChannelCode;
}

export function parseMarketplaceListingType(
  value: unknown,
): MarketplaceListingTypeCode {
  const resolved = requiredString(
    value,
    "MARKETPLACE_LISTING_TYPE_REQUIRED",
    100,
  ).toUpperCase();

  if (
    !MARKETPLACE_LISTING_TYPE_CODES.includes(
      resolved as MarketplaceListingTypeCode,
    )
  ) {
    throw new Error("MARKETPLACE_LISTING_TYPE_INVALID");
  }

  return resolved as MarketplaceListingTypeCode;
}

export function parseMarketplaceListingComponents(
  value: unknown,
): MarketplaceListingDraftComponent[] {
  let parsed = value;

  if (typeof value === "string") {
    try {
      parsed = JSON.parse(value);
    } catch {
      throw new Error("MARKETPLACE_BUNDLE_COMPONENTS_INVALID");
    }
  }

  if (!Array.isArray(parsed)) {
    throw new Error("MARKETPLACE_BUNDLE_COMPONENTS_INVALID");
  }

  if (parsed.length > 100) {
    throw new Error("MARKETPLACE_BUNDLE_COMPONENTS_LIMIT_EXCEEDED");
  }

  const components = parsed.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("MARKETPLACE_BUNDLE_COMPONENT_INVALID");
    }

    const record = item as Record<string, unknown>;
    const productId = requiredString(
      record.productId,
      "MARKETPLACE_BUNDLE_COMPONENT_PRODUCT_REQUIRED",
      36,
    );
    const quantity = Number(record.quantity);

    if (!UUID_PATTERN.test(productId)) {
      throw new Error("MARKETPLACE_BUNDLE_COMPONENT_PRODUCT_INVALID");
    }

    if (
      !Number.isSafeInteger(quantity) ||
      quantity <= 0 ||
      quantity > 999_999_999
    ) {
      throw new Error("MARKETPLACE_BUNDLE_COMPONENT_QUANTITY_INVALID");
    }

    return { productId, quantity };
  });

  const productIds = components.map((component) => component.productId);

  if (new Set(productIds).size !== productIds.length) {
    throw new Error("MARKETPLACE_BUNDLE_COMPONENT_DUPLICATE");
  }

  return components;
}

export function marketplaceListingAdminErrorMessage(error: unknown) {
  const raw =
    error instanceof Error
      ? error.message
      : "Terjadi kesalahan yang tidak diketahui.";

  const messages: Record<string, string> = {
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    ORGANIZATION_NOT_FOUND:
      "Organisasi aktif tidak ditemukan.",
    ORGANIZATION_REQUIRED:
      "Organisasi aktif wajib tersedia.",
    IDEMPOTENCY_KEY_REQUIRED:
      "Referensi proses tidak tersedia. Muat ulang halaman dan coba lagi.",
    IDEMPOTENCY_KEY_REUSED:
      "Referensi proses sudah dipakai untuk payload yang berbeda.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Perintah yang sama masih diproses. Muat ulang untuk melihat hasilnya.",
    MARKETPLACE_CHANNEL_REQUIRED:
      "Channel marketplace wajib dipilih.",
    MARKETPLACE_CHANNEL_NOT_ALLOWED:
      "Channel marketplace tersebut tidak didukung.",
    MARKETPLACE_LISTING_CODE_REQUIRED:
      "Kode listing marketplace wajib diisi.",
    MARKETPLACE_LISTING_CODE_TOO_LONG:
      "Kode listing marketplace maksimal 200 karakter.",
    MARKETPLACE_LISTING_NAME_INVALID:
      "Nama listing wajib diisi dan maksimal 300 karakter.",
    MARKETPLACE_LISTING_TYPE_REQUIRED:
      "Jenis listing wajib dipilih.",
    MARKETPLACE_LISTING_TYPE_INVALID:
      "Jenis listing harus SINGLE atau BUNDLE.",
    MARKETPLACE_LISTING_TYPE_MISMATCH:
      "Jenis listing tidak sama dengan listing yang sudah terdaftar.",
    MARKETPLACE_LISTING_ALREADY_ARCHIVED:
      "Listing marketplace sudah diarsipkan.",
    MARKETPLACE_LISTING_ARCHIVED:
      "Listing marketplace sudah diarsipkan.",
    MARKETPLACE_LISTING_NOT_FOUND:
      "Listing marketplace tidak ditemukan.",
    MARKETPLACE_LISTING_VERSION_REQUIRED:
      "Versi listing wajib dipilih.",
    MARKETPLACE_LISTING_VERSION_NOT_FOUND:
      "Versi listing tidak ditemukan.",
    MARKETPLACE_LISTING_VERSION_NOT_DRAFT:
      "Hanya versi draft yang dapat diubah.",
    MARKETPLACE_LISTING_EFFECTIVE_FROM_REQUIRED:
      "Waktu mulai berlaku wajib diisi.",
    MARKETPLACE_LISTING_ROW_VERSION_INVALID:
      "Versi perubahan data tidak valid. Muat ulang halaman.",
    STALE_MARKETPLACE_LISTING:
      "Listing berubah sejak halaman dibuka. Muat ulang sebelum mencoba lagi.",
    STALE_MARKETPLACE_LISTING_VERSION_DRAFT:
      "Draft berubah sejak halaman dibuka. Muat ulang sebelum menyimpan.",
    STALE_MARKETPLACE_LISTING_ACTIVATION_PREVIEW:
      "Draft atau mapping berubah setelah preview. Tinjau preview terbaru.",
    MARKETPLACE_LISTING_PREVIEW_HASH_INVALID:
      "Basis preview aktivasi tidak valid. Tinjau ulang draft.",
    MARKETPLACE_LISTING_ACTIVATION_BLOCKED:
      "Versi belum dapat diaktifkan karena masih memiliki blocker.",
    MARKETPLACE_LISTING_ACTIVATION_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang sebelum aktivasi.",
    MARKETPLACE_LISTING_ACTIVATION_TIME_STALE:
      "Waktu efektif versi baru harus setelah versi aktif saat ini.",
    MARKETPLACE_LISTING_RETIREMENT_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang sebelum menghentikan versi.",
    MARKETPLACE_LISTING_RETIREMENT_TIME_REQUIRED:
      "Waktu berhenti berlaku wajib diisi.",
    MARKETPLACE_LISTING_RETIREMENT_TIME_INVALID:
      "Waktu berhenti berlaku harus setelah waktu mulai berlaku.",
    MARKETPLACE_LISTING_ARCHIVE_CONFIRMATION_REQUIRED:
      "Konfirmasi final wajib dicentang sebelum mengarsipkan listing.",
    MARKETPLACE_LISTING_HAS_OPEN_VERSION:
      "Listing masih memiliki versi aktif atau draft yang harus diselesaikan.",
    MARKETPLACE_SINGLE_PRODUCT_REQUIRED:
      "Listing SINGLE wajib memilih satu produk aktif.",
    MARKETPLACE_SINGLE_PRODUCT_INACTIVE:
      "Produk untuk listing SINGLE sedang tidak aktif.",
    MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED:
      "Listing BUNDLE wajib memiliki minimal satu komponen.",
    MARKETPLACE_BUNDLE_COMPONENTS_INVALID:
      "Daftar komponen bundle tidak dapat dibaca.",
    MARKETPLACE_BUNDLE_COMPONENT_INVALID:
      "Salah satu komponen bundle tidak valid.",
    MARKETPLACE_BUNDLE_COMPONENT_PRODUCT_REQUIRED:
      "Produk wajib dipilih untuk setiap komponen bundle.",
    MARKETPLACE_BUNDLE_COMPONENT_PRODUCT_INVALID:
      "Identitas produk komponen tidak valid.",
    MARKETPLACE_BUNDLE_COMPONENT_QUANTITY_INVALID:
      "Quantity komponen harus berupa bilangan bulat positif.",
    MARKETPLACE_BUNDLE_COMPONENT_DUPLICATE:
      "Produk yang sama tidak boleh muncul dua kali dalam satu resep.",
    MARKETPLACE_BUNDLE_COMPONENT_INACTIVE:
      "Salah satu produk komponen bundle sedang tidak aktif.",
    MARKETPLACE_BUNDLE_COMPONENTS_LIMIT_EXCEEDED:
      "Jumlah komponen bundle melebihi batas.",
    MARKETPLACE_LISTING_METADATA_MUST_BE_OBJECT:
      "Metadata listing tidak valid.",
  };

  const matched = Object.keys(messages)
    .sort((left, right) => right.length - left.length)
    .find((code) => raw.includes(code));

  return matched ? messages[matched] : raw;
}

export function jakartaTimestamp(value: string) {
  const resolved = value.trim();

  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(resolved) ||
    Number.isNaN(new Date(`${resolved}:00+07:00`).getTime())
  ) {
    throw new Error("Waktu lokal tidak valid.");
  }

  return `${resolved}:00+07:00`;
}