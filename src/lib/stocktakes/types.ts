export const STOCKTAKE_STATUSES = [
  "DRAFT",
  "READY",
  "COUNTING",
  "REVIEW",
  "APPROVED",
  "POSTING",
  "POSTED",
  "CANCELLED",
  "EXCEPTION",
] as const;

export const STOCKTAKE_TYPES = ["FULL", "CYCLE", "AD_HOC"] as const;

export const STOCKTAKE_VISIBILITIES = ["BLIND", "NON_BLIND"] as const;

export type StocktakeStatus = (typeof STOCKTAKE_STATUSES)[number];
export type StocktakeType = (typeof STOCKTAKE_TYPES)[number];
export type StocktakeVisibility = (typeof STOCKTAKE_VISIBILITIES)[number];

export type StocktakeListItem = {
  stocktake_id: string;
  organization_id: string;
  stocktake_no: string;
  title: string;
  stocktake_type_code: StocktakeType;
  mode_code: "CONTINUOUS";
  visibility_code: StocktakeVisibility;
  status_code: StocktakeStatus;
  planned_at: string | null;
  snapshot_ledger_seq: number | null;
  started_at: string | null;
  counting_completed_at: string | null;
  created_at: string;
  updated_at: string;
  version_no: number;
  line_count: number;
  counted_line_count: number;
  variance_line_count: number;
};