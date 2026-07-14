import {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_STATUSES,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
  type StocktakeBucket,
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