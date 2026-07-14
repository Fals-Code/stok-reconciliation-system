import {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_STATUSES,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
  type StocktakeBucket,
  type StocktakeCountStatus,
  type StocktakeReviewDecision,
  type StocktakeVarianceReason,
  type StocktakeListItem,
  type StocktakeScopeMode,
  type StocktakeStatus,
  type StocktakeType,
  type StocktakeVisibility,
} from "@/lib/stocktakes/types";

export type StocktakePillTone = "success" | "warning" | "danger" | "neutral";

export const STOCKTAKE_STATUS_META: Record<
  StocktakeStatus,
  { label: string; tone: StocktakePillTone }
> = {
  DRAFT: { label: "Draft", tone: "neutral" },
  READY: { label: "Siap dimulai", tone: "neutral" },
  COUNTING: { label: "Penghitungan", tone: "warning" },
  REVIEW: { label: "Review", tone: "warning" },
  APPROVED: { label: "Disetujui", tone: "warning" },
  POSTING: { label: "Sedang posting", tone: "warning" },
  POSTED: { label: "Sudah diposting", tone: "success" },
  CANCELLED: { label: "Dibatalkan", tone: "danger" },
  EXCEPTION: { label: "Exception", tone: "danger" },
};

export const STOCKTAKE_TYPE_LABELS: Record<StocktakeType, string> = {
  FULL: "Full inventory",
  CYCLE: "Cycle count",
  AD_HOC: "Ad hoc",
};

export const STOCKTAKE_VISIBILITY_LABELS: Record<StocktakeVisibility, string> = {
  BLIND: "Blind",
  NON_BLIND: "Non-blind",
};

export const STOCKTAKE_SCOPE_LABELS: Record<StocktakeScopeMode, string> = {
  ALL_ACTIVE_INVENTORY: "Seluruh inventory aktif",
  PRODUCTS: "Produk terpilih",
  BATCHES: "Batch terpilih",
};

export const STOCKTAKE_BUCKET_LABELS: Record<StocktakeBucket, string> = {
  SELLABLE: "Sellable",
  QUARANTINE: "Quarantine",
  DAMAGED: "Damaged",
};


export const STOCKTAKE_COUNT_STATUS_META: Record<
  StocktakeCountStatus,
  { label: string; tone: StocktakePillTone }
> = {
  PENDING: { label: "Belum dihitung", tone: "neutral" },
  COUNTED: { label: "Tersimpan", tone: "success" },
  RECOUNT_REQUESTED: { label: "Perlu hitung ulang", tone: "warning" },
};

const FINAL_STATUSES = new Set<StocktakeStatus>(["POSTED", "CANCELLED"]);

export function isActiveStocktake(status: StocktakeStatus) {
  return !FINAL_STATUSES.has(status);
}

export function stocktakeProgress(stocktake: StocktakeListItem) {
  const lineCount = Number(stocktake.line_count);
  const countedLineCount = Number(stocktake.counted_line_count);

  if (lineCount <= 0) {
    return 0;
  }

  return Math.min(100, Math.round((countedLineCount / lineCount) * 100));
}

export {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_STATUSES,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
};

export const STOCKTAKE_REVIEW_DECISION_META: Record<
  StocktakeReviewDecision,
  { label: string; tone: StocktakePillTone }
> = {
  MATCHED: { label: "Matched", tone: "success" },
  VARIANCE_ACCEPTED: { label: "Variance diterima", tone: "warning" },
  RECOUNT_REQUIRED: { label: "Recount diminta", tone: "warning" },
  EXCEPTION: { label: "Exception", tone: "danger" },
};

export const STOCKTAKE_VARIANCE_REASON_LABELS: Record<
  StocktakeVarianceReason,
  string
> = {
  UNRECORDED_MANUAL_OUTBOUND: "Manual outbound belum tercatat",
  UNRECORDED_INBOUND: "Inbound belum tercatat",
  RETURN_MISMATCH: "Ketidaksesuaian return",
  WRONG_BATCH_COUNT: "Salah hitung batch",
  WRONG_BUCKET_COUNT: "Salah hitung bucket",
  DAMAGE_NOT_RECORDED: "Kerusakan belum tercatat",
  EXPIRY_NOT_RECORDED: "Expiry belum tercatat",
  INITIAL_BALANCE_UNCERTAIN: "Saldo awal tidak pasti",
  COUNT_TIMING_DIFFERENCE: "Perbedaan waktu counting",
  DUPLICATE_MOVEMENT: "Movement duplikat",
  SOURCE_EVENT_FAILURE: "Kegagalan source event",
  PROJECTION_DRIFT: "Projection drift",
  PHYSICAL_LOSS: "Kehilangan fisik",
  PHYSICAL_SURPLUS: "Surplus fisik",
  MASTER_DATA_ERROR: "Kesalahan master data",
  UNKNOWN: "Belum diketahui",
  OTHER: "Lainnya",
};

export const STOCKTAKE_VARIANCE_REASON_OPTIONS = Object.entries(
  STOCKTAKE_VARIANCE_REASON_LABELS,
).map(([value, label]) => ({
  value: value as StocktakeVarianceReason,
  label,
}));
