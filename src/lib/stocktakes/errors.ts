function rawErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "Terjadi kesalahan yang tidak diketahui.";
}

const STOCKTAKE_ERROR_MESSAGES: Record<string, string> = {
  AUTHENTICATION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
  AUTH_SESSION_REQUIRED: "Sesi Admin sudah berakhir. Silakan login kembali.",
  ORGANIZATION_ACCESS_DENIED:
    "Sesi stocktake tidak dapat dibuat untuk organisasi lain.",
  ORGANIZATION_NOT_FOUND: "Organisasi Admin tidak ditemukan atau tidak aktif.",
  IDEMPOTENCY_KEY_REQUIRED: "Referensi permintaan stocktake wajib tersedia.",
  IDEMPOTENCY_KEY_TOO_LONG: "Referensi permintaan stocktake terlalu panjang.",
  IDEMPOTENCY_KEY_REUSED:
    "Referensi permintaan sudah digunakan untuk payload stocktake yang berbeda.",
  IDEMPOTENCY_COMMAND_IN_PROGRESS:
    "Permintaan stocktake yang sama masih diproses.",
  IDEMPOTENCY_COMMAND_FAILED:
    "Permintaan stocktake sebelumnya gagal dan perlu diperiksa.",
  STOCKTAKE_ID_REQUIRED: "ID stocktake tidak valid.",
  STOCKTAKE_NOT_FOUND:
    "Sesi stocktake tidak ditemukan pada organisasi Admin saat ini.",
  STOCKTAKE_INVALID_STATE:
    "Aksi ini tidak valid untuk status stocktake saat ini. Muat ulang halaman.",
  STOCKTAKE_TITLE_REQUIRED: "Judul stocktake wajib diisi.",
  STOCKTAKE_TITLE_TOO_LONG: "Judul stocktake maksimal 200 karakter.",
  STOCKTAKE_TYPE_NOT_SUPPORTED: "Tipe stocktake tidak didukung.",
  STOCKTAKE_MODE_NOT_SUPPORTED:
    "Fase pertama hanya mendukung mode CONTINUOUS.",
  STOCKTAKE_VISIBILITY_NOT_SUPPORTED:
    "Visibility stocktake tidak didukung.",
  STOCKTAKE_SCOPE_REQUIRED:
    "Scope stocktake belum lengkap. Pilih bucket dan entitas yang diperlukan.",
  STOCKTAKE_SCOPE_NOT_SUPPORTED:
    "Kombinasi scope stocktake tidak didukung.",
  STOCKTAKE_SCOPE_DUPLICATE_ENTITY:
    "Scope stocktake mengandung produk, batch, atau bucket duplikat.",
  STOCKTAKE_SCOPE_EMPTY:
    "Scope stocktake tidak menghasilkan inventory yang dapat dihitung.",
  STOCKTAKE_SCOPE_ENTITY_NOT_FOUND:
    "Produk atau batch pada scope tidak lagi tersedia dalam organisasi ini.",
  STOCKTAKE_SNAPSHOT_INCOMPLETE:
    "Snapshot atau count line tidak dapat dibuat secara lengkap. Sesi tidak dimulai.",
  STOCKTAKE_START_CONFIRMATION_REQUIRED:
    "Konfirmasi pembuatan snapshot dan count line wajib diberikan.",
  STOCKTAKE_LINE_ID_REQUIRED: "ID line stocktake tidak valid.",
  STOCKTAKE_LINE_NOT_FOUND:
    "Line stocktake tidak ditemukan pada sesi atau organisasi ini.",
  STOCKTAKE_INVALID_PHYSICAL_QTY:
    "Quantity fisik wajib berupa bilangan bulat nol atau lebih.",
  STOCKTAKE_ZERO_CONFIRMATION_REQUIRED:
    "Quantity fisik nol harus dikonfirmasi secara eksplisit.",
  STOCKTAKE_COUNT_METHOD_NOT_SUPPORTED:
    "UI fase pertama hanya mengirim count dengan metode MANUAL_ENTRY.",
  STOCKTAKE_COUNT_CONFLICT:
    "Line sudah dihitung atau statusnya berubah. Muat ulang sebelum mencoba lagi.",
  STOCKTAKE_RECOUNT_REASON_REQUIRED:
    "Alasan hitung ulang wajib diisi.",
  STOCKTAKE_RECOUNT_REASON_TOO_LONG:
    "Alasan hitung ulang maksimal 2.000 karakter.",
  STOCKTAKE_COUNT_REQUIRED:
    "Semua line wajib memiliki count valid sebelum counting diselesaikan.",
  STOCKTAKE_COUNTING_INCOMPLETE:
    "Counting belum lengkap. Selesaikan seluruh line sebelum melanjutkan.",
  STOCKTAKE_ATTEMPT_NO_INVALID:
    "Nomor attempt line tidak valid. Muat ulang halaman.",
  STOCKTAKE_VERSION_INVALID:
    "Versi stocktake tidak valid. Muat ulang halaman.",
  STOCKTAKE_LINE_VERSION_REQUIRED:
    "Versi line wajib tersedia sebelum review.",
  STOCKTAKE_LINE_VERSION_CONFLICT:
    "Line sudah berubah sejak halaman dibuka. Muat ulang dan tinjau versi terbaru.",
  STOCKTAKE_REVIEW_INVALID_STATE:
    "Sesi tidak lagi berada pada tahap Review.",
  STOCKTAKE_REVIEW_DECISION_REQUIRED:
    "Keputusan review wajib dipilih.",
  STOCKTAKE_REVIEW_DECISION_INVALID:
    "Keputusan review tidak sesuai dengan nilai variance line.",
  STOCKTAKE_REASON_REQUIRED:
    "Reason wajib dipilih untuk menerima variance.",
  STOCKTAKE_REASON_NOT_SUPPORTED:
    "Reason variance tidak didukung oleh kontrak server.",
  STOCKTAKE_REVIEW_NOTE_REQUIRED:
    "Catatan review wajib diisi untuk reason UNKNOWN atau OTHER.",
  STOCKTAKE_REVIEW_NOTE_TOO_LONG:
    "Catatan review maksimal 2.000 karakter.",
  STOCKTAKE_EXCEPTION_REQUIRED:
    "Kode exception wajib diisi.",
  STOCKTAKE_EXCEPTION_CODE_TOO_LONG:
    "Kode exception maksimal 100 karakter.",
  STOCKTAKE_NOTE_TOO_LONG: "Catatan stocktake maksimal 2.000 karakter.",
  STOCKTAKE_METADATA_MUST_BE_OBJECT:
    "Metadata stocktake tidak valid.",
  STOCKTAKE_PLANNED_AT_INVALID:
    "Tanggal dan waktu rencana stocktake tidak valid.",
};

export function stocktakeErrorMessage(error: unknown) {
  const raw = rawErrorMessage(error);
  const matched = Object.entries(STOCKTAKE_ERROR_MESSAGES).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}