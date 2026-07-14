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

export const STOCKTAKE_SCOPE_MODES = [
  "ALL_ACTIVE_INVENTORY",
  "PRODUCTS",
  "BATCHES",
] as const;

export const STOCKTAKE_BUCKETS = [
  "SELLABLE",
  "QUARANTINE",
  "DAMAGED",
] as const;

export type StocktakeStatus = (typeof STOCKTAKE_STATUSES)[number];
export type StocktakeType = (typeof STOCKTAKE_TYPES)[number];
export type StocktakeVisibility = (typeof STOCKTAKE_VISIBILITIES)[number];
export type StocktakeScopeMode = (typeof STOCKTAKE_SCOPE_MODES)[number];
export type StocktakeBucket = (typeof STOCKTAKE_BUCKETS)[number];

export type StocktakeScopeDefinition = {
  mode: StocktakeScopeMode;
  bucketCodes: StocktakeBucket[];
  includeZeroSystemBalance: boolean;
  includeInactiveWithBalance: boolean;
  includeBlockedBatches: boolean;
  includeExpiredBatches: boolean;
  productIds?: string[];
  batchIds?: string[];
};

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
  variance_line_count: number | null;
};

export type StocktakeDetails = {
  stocktake_id: string;
  organization_id: string;
  stocktake_no: string;
  title: string;
  stocktake_type_code: StocktakeType;
  mode_code: "CONTINUOUS";
  visibility_code: StocktakeVisibility;
  status_code: StocktakeStatus;
  scope_definition: StocktakeScopeDefinition;
  tolerance_policy_snapshot: {
    units: number;
    percent: number;
  };
  rule_version: string;
  timezone_snapshot: string;
  planned_at: string | null;
  snapshot_ledger_seq: number | null;
  started_at: string | null;
  counting_completed_at: string | null;
  approved_at: string | null;
  posted_at: string | null;
  stock_transaction_id: string | null;
  reconciliation_run_id: string | null;
  created_by: string | null;
  process_name: string | null;
  note: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  version_no: number;
};

export type StocktakeProductOption = {
  product_id: string;
  organization_id: string;
  sku: string;
  name: string;
  is_active: boolean;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
};

export type StocktakeBatchOption = {
  batch_id: string;
  organization_id: string;
  product_id: string;
  sku: string;
  product_name: string;
  batch_code: string;
  expiry_date: string;
  status_code: string;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
};

export type StocktakeCreateOptions = {
  products: StocktakeProductOption[];
  batches: StocktakeBatchOption[];
};

export type StocktakeCreateResponse = {
  status: "DRAFT";
  stocktakeId: string;
  stocktakeNo: string;
  stocktakeTypeCode: StocktakeType;
  modeCode: "CONTINUOUS";
  visibilityCode: StocktakeVisibility;
  scope: StocktakeScopeDefinition;
  idempotencyKey: string;
  requestHash: string;
  createdAt: string;
};

export type StocktakePrepareResponse = {
  status: "READY";
  stocktakeId: string;
  stocktakeNo: string;
  scopeLineCount: number;
  validationLedgerSeq: number;
  idempotencyKey: string;
  requestHash: string;
  preparedAt: string;
};

export type StocktakeStartResponse = {
  status: "COUNTING";
  stocktakeId: string;
  stocktakeNo: string;
  snapshotLedgerSeq: number;
  snapshotSource: "LEDGER";
  lineCount: number;
  idempotencyKey: string;
  requestHash: string;
  startedAt: string;
};

export type StocktakeDetailData = {
  details: StocktakeDetails;
  summary: StocktakeListItem | null;
};

export type StocktakeCountStatus =
  | "PENDING"
  | "COUNTED"
  | "RECOUNT_REQUESTED";

export type StocktakeReviewStatus = "PENDING" | "READY" | "REVIEWED";

export type StocktakeCountingLineBase = {
  stocktake_line_id: string;
  organization_id: string;
  stocktake_id: string;
  line_no: number;
  product_id: string;
  batch_id: string;
  bucket_code: StocktakeBucket;
  product_sku_snapshot: string;
  product_name_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  final_physical_qty: number | null;
  count_attempt_no: number;
  count_status_code: StocktakeCountStatus;
  review_status_code: StocktakeReviewStatus;
  exception_code: string | null;
  created_at: string;
  updated_at: string;
  version_no: number;
};

export type StocktakeBlindLine = StocktakeCountingLineBase;

export type StocktakeNonBlindLine = StocktakeCountingLineBase & {
  system_qty_at_snapshot: number;
  final_attempt_id: string | null;
  expected_qty_at_count: number | null;
  variance_qty: number | null;
  count_cutoff_ledger_seq: number | null;
  expected_formula_version: string | null;
};

export type StocktakeCountingLine =
  | StocktakeBlindLine
  | StocktakeNonBlindLine;

export type StocktakeCountResponse = {
  status: "COUNTED";
  stocktakeId: string;
  stocktakeLineId: string;
  countAttemptId: string;
  attemptNo: number;
  physicalQty: number;
  countCutoffLedgerSeq: number;
  countMethodCode: "MANUAL_ENTRY";
  zeroConfirmed: boolean;
  countStatusCode: "COUNTED";
  reviewStatusCode: "READY";
  visibilityCode: StocktakeVisibility;
  idempotencyKey: string;
  requestHash: string;
  countedAt: string;
  expectedQty?: number;
  varianceQty?: number;
  expectedFormulaVersion?: string;
};

export type StocktakeRecountResponse = {
  status: "RECOUNT_REQUESTED";
  stocktakeId: string;
  stocktakeLineId: string;
  currentAttemptNo: number;
  currentCountAttemptId: string;
  reason: string;
  countStatusCode: "RECOUNT_REQUESTED";
  reviewStatusCode: "PENDING";
  idempotencyKey: string;
  requestHash: string;
  requestedAt: string;
  requestedByUserId: string | null;
  requestedByProcessName: string | null;
};

export type StocktakeCompleteCountingResponse = {
  status: "REVIEW";
  stocktakeId: string;
  stocktakeNo: string;
  lineCount: number;
  countedLineCount: number;
  varianceLineCount: number;
  totalVarianceQty: number;
  idempotencyKey: string;
  requestHash: string;
  countingCompletedAt: string;
};
