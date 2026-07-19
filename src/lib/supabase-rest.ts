import "server-only";

import { getAccessToken, getAdminSession } from "@/lib/auth";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";

export type ProductInventory = {
  product_id: string;
  organization_id: string;
  sku: string;
  name: string;
  unit_code: string;
  is_active: boolean;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
  reserved_qty: number;
  available_qty: number;
  last_ledger_seq: number;
  stock_updated_at: string | null;
};

export type BatchInventory = {
  batch_id: string;
  organization_id: string;
  product_id: string;
  sku: string;
  product_name: string;
  batch_code: string;
  expiry_date: string;
  received_first_at: string | null;
  status_code: string;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
  last_ledger_seq: number;
  stock_updated_at: string | null;
  batch_kind_code: "STANDARD" | "RETURN" | "UNIDENTIFIED_RETURN";
};

export type StockLedgerEntry = {
  ledger_seq: number;
  ledger_entry_id: string;
  organization_id: string;
  transaction_id: string;
  transaction_no: string;
  transaction_type_code: string;
  reason_code_snapshot: string;
  channel_code_snapshot: string;
  source_type_code: string;
  source_ref_snapshot: string;
  line_no: number;
  product_id: string;
  batch_id: string;
  product_sku_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  bucket_code: string;
  quantity_delta: number;
  entry_role_code: string;
  source_line_ref: string | null;
  occurred_at: string;
  recorded_at: string;
  note: string | null;
  correlation_id: string;
};

export type MarketplaceOrder = {
  order_id: string;
  organization_id: string;
  channel_code: string;
  external_order_ref: string;
  status_code: string;
  reserved_at: string;
  closed_at: string | null;
  actor_user_id: string | null;
  process_name: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  reserved_qty: number;
  shipped_qty: number;
  released_qty: number;
  open_qty: number;
};

export type MarketplaceReservation = {
  organization_id: string;
  order_id: string;
  channel_code: string;
  external_order_ref: string;
  order_item_id: string;
  line_no: number;
  external_item_ref: string;
  product_id: string;
  product_sku_snapshot: string;
  quantity_ordered: number;
  reservation_id: string;
  reserved_qty: number;
  consumed_qty: number;
  released_qty: number;
  open_qty: number;
  status_code: string;
  reserved_at: string;
  closed_at: string | null;
};

export type MarketplaceEvent = {
  event_id: string;
  organization_id: string;
  order_id: string;
  channel_code: string;
  external_event_ref: string;
  event_type_code: string;
  status_code: string;
  occurred_at: string;
  recorded_at: string;
  actor_user_id: string | null;
  process_name: string | null;
  transaction_id: string | null;
  note: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type MarketplaceShipAllocation = {
  allocation_id: string;
  organization_id: string;
  event_id: string;
  event_line_id: string;
  allocation_no: number;
  ledger_entry_id: string;
  product_id: string;
  batch_id: string;
  quantity_allocated: number;
  product_sku_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  received_first_at_snapshot: string | null;
  source_line_ref: string;
  created_at: string;
};

export type ReturnHeader = {
  return_id: string;
  organization_id: string;
  channel_code: string;
  marketplace_order_id: string;
  marketplace_order_ref: string;
  external_return_ref: string;
  source_status_code: string | null;
  status_code: string;
  outcome_code: string | null;
  expected_at: string;
  closed_at: string | null;
  actor_user_id: string | null;
  process_name: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  expected_qty: number;
  received_qty: number;
  sellable_qty: number;
  damaged_qty: number;
  lost_qty: number;
  pending_arrival_qty: number;
  pending_inspection_qty: number;
};

export type ReturnItem = {
  return_item_id: string;
  organization_id: string;
  return_id: string;
  line_no: number;
  marketplace_order_item_id: string;
  marketplace_item_ref: string;
  product_id: string;
  product_sku_snapshot: string;
  source_line_ref: string;
  expected_qty: number;
  received_qty: number;
  sellable_qty: number;
  damaged_qty: number;
  lost_qty: number;
  pending_arrival_qty: number;
  pending_inspection_qty: number;
  created_at: string;
  updated_at: string;
};

export type ReturnEvent = {
  event_id: string;
  organization_id: string;
  return_id: string;
  external_event_ref: string;
  event_type_code: string;
  occurred_at: string;
  recorded_at: string;
  actor_user_id: string | null;
  process_name: string | null;
  transaction_id: string | null;
  note: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type ReturnReceiptLine = {
  receipt_line_id: string;
  organization_id: string;
  return_id: string;
  receipt_id: string;
  receipt_ref: string;
  return_item_id: string;
  marketplace_ship_allocation_id: string | null;
  line_no: number;
  product_id: string;
  batch_id: string | null;
  quantity_received: number;
  batch_identity_verified: boolean;
  product_sku_snapshot: string;
  batch_code_snapshot: string | null;
  expiry_date_snapshot: string | null;
  source_line_ref: string;
  ledger_entry_id: string | null;
  occurred_at: string;
  created_at: string;
  stock_effect_code: "NONE" | "LEGACY_QUARANTINE_INBOUND";
  source_batch_id: string | null;
  source_batch_code_snapshot: string | null;
  source_expiry_date_snapshot: string | null;
};

export type ReturnInspectionAllocation = {
  inspection_allocation_id: string;
  organization_id: string;
  return_id: string;
  inspection_id: string;
  inspection_ref: string;
  receipt_line_id: string;
  allocation_no: number;
  destination_bucket_code: "SELLABLE" | "DAMAGED" | null;
  quantity_allocated: number;
  pair_no: number | null;
  source_ledger_entry_id: string | null;
  destination_ledger_entry_id: string | null;
  occurred_at: string;
  created_at: string;
  condition_code: "SELLABLE" | "DAMAGED";
  stock_effect_code: "NONE" | "SELLABLE_INBOUND" | "LEGACY_TRANSFER";
  return_batch_id: string | null;
};
export type ReconciliationRun = {
  run_id: string;
  organization_id: string;
  run_no: string;
  run_type_code: string;
  trigger_code: string;
  status_code: string;
  scope: Record<string, unknown>;
  check_codes: string[];
  rule_set_version: string;
  ledger_seq_from: number;
  ledger_seq_to: number;
  started_at: string;
  completed_at: string | null;
  actor_user_id: string | null;
  process_name: string | null;
  summary: Record<string, unknown>;
  error_code: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type ReconciliationCheck = {
  run_check_id: string;
  organization_id: string;
  run_id: string;
  check_code: string;
  rule_version: string;
  status_code: string;
  checked_count: number;
  issue_count: number;
  started_at: string | null;
  completed_at: string | null;
  summary: Record<string, unknown>;
  error_code: string | null;
  created_at: string;
  updated_at: string;
};

export type ReconciliationIssue = {
  issue_id: string;
  organization_id: string;
  fingerprint: string;
  check_code: string;
  rule_version: string;
  status_code: "OPEN" | "RESOLVED";
  severity_code: "INFO" | "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
  entity_type_code: string;
  entity_key: Record<string, unknown>;
  product_id: string | null;
  batch_id: string | null;
  source_type_code: string | null;
  source_ref: string | null;
  expected_value: unknown;
  actual_value: unknown;
  difference_value: unknown;
  first_seen_run_id: string;
  last_seen_run_id: string;
  first_seen_at: string;
  last_seen_at: string;
  recurrence_count: number;
  resolved_at: string | null;
  resolution_code: string | null;
  resolution_note: string | null;
  created_at: string;
  updated_at: string;
};

export type ReconciliationIssueEvidence = {
  evidence_id: string;
  organization_id: string;
  issue_id: string;
  run_id: string;
  run_check_id: string;
  evidence_no: number;
  evidence_type_code: string;
  entity_type_code: string;
  entity_key: Record<string, unknown>;
  expected_value: unknown;
  actual_value: unknown;
  difference_value: unknown;
  detail: Record<string, unknown>;
  created_at: string;
};

export type ReconciliationData = {
  runs: ReconciliationRun[];
  checks: ReconciliationCheck[];
  issues: ReconciliationIssue[];
  evidence: ReconciliationIssueEvidence[];
};
export type NotificationListItem = {
  notification_id: string;
  rule_code: string;
  notification_type_code: string;
  category_code: string;
  entity_type_code: string;
  entity_id: string;
  episode_no: number;
  lifecycle_status_code: "OPEN" | "ACKNOWLEDGED" | "RESOLVED";
  stage_code: string;
  severity_code: "INFO" | "WARNING" | "HIGH" | "CRITICAL";
  title: string;
  message: string;
  action_code: string;
  action_route: string | null;
  condition_started_at: string;
  due_at: string | null;
  first_seen_at: string;
  last_seen_at: string;
  occurrence_count: number;
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  acknowledgment_note: string | null;
  resolved_at: string | null;
  resolution_code: string | null;
  read_state_code: "UNREAD" | "READ" | "ARCHIVED_FOR_USER";
  read_at: string | null;
  archived_at: string | null;
  version_no: number;
};

export type NotificationDetail = NotificationListItem & {
  previous_notification_id: string | null;
  rule_id: string;
  rule_version: string;
  template_version: string;
  last_reminded_at: string | null;
  acknowledged_by_display_name: string | null;
  resolution_snapshot: Record<string, unknown>;
  source_snapshot: Record<string, unknown>;
  config_snapshot: Record<string, unknown>;
  last_seen_version_no: number | null;
  created_at: string;
  updated_at: string;
};

export type NotificationEventHistoryItem = {
  event_id: string;
  event_type_code: string;
  from_lifecycle_status_code: string | null;
  to_lifecycle_status_code: string | null;
  from_stage_code: string | null;
  to_stage_code: string | null;
  from_severity_code: string | null;
  to_severity_code: string | null;
  source_snapshot: Record<string, unknown>;
  note: string | null;
  actor_type_code: string;
  actor_user_id: string | null;
  actor_display_name: string | null;
  process_name: string | null;
  occurred_at: string;
  correlation_id: string;
};

export type NotificationListFilters = {
  lifecycleStatusCode?: string | null;
  severityCode?: string | null;
  categoryCode?: string | null;
  readStateCode?: string | null;
  includeArchived?: boolean;
  limit?: number;
  beforeLastSeenAt?: string | null;
  beforeId?: string | null;
};

export type NotificationReadStateCode =
  | "UNREAD"
  | "READ"
  | "ARCHIVED_FOR_USER";

export type NotificationReadStateMutationResponse = {
  notificationId: string;
  userId: string;
  action:
    | "SET_UNREAD"
    | "SET_READ"
    | "SET_ARCHIVED"
    | "ALREADY_UNREAD"
    | "ALREADY_READ"
    | "ALREADY_ARCHIVED";
  readStateCode: NotificationReadStateCode;
  notificationVersionNo: number;
};

export type NotificationLifecycleMutationResponse = {
  notificationId: string;
  action:
    | "ACKNOWLEDGED"
    | "ALREADY_ACKNOWLEDGED"
    | "ACKNOWLEDGMENT_REVOKED"
    | "ALREADY_OPEN";
  lifecycleStatusCode: "OPEN" | "ACKNOWLEDGED";
  acknowledgedAt?: string | null;
  acknowledgedBy?: string | null;
  versionNo: number;
};


export type NotificationEvaluationFamilyCode =
  | "EXPIRY"
  | "RETURN_INSPECTION"
  | "RECONCILIATION"
  | "STOCKTAKE";

export type NotificationOperationsSummary = {
  organizationId: string;
  userId: string;
  generatedAt: string;
  staleLockTimeoutSeconds: number;
  outbox: {
    pendingCount: number;
    processingCount: number;
    failedRetryableCount: number;
    failedFinalCount: number;
    completedCount: number;
    actionableCount: number;
    staleProcessingCount: number;
    oldestActionableAt: string | null;
  };
  ruleRuns: {
    startedCount: number;
    succeededLast24Hours: number;
    partiallyFailedLast24Hours: number;
    failedLast24Hours: number;
  };
  notifications: {
    openCount: number;
    acknowledgedCount: number;
    criticalActiveCount: number;
    highActiveCount: number;
    unreadCount: number;
  };
  adminOperations: {
    retryRequestsLast24Hours: number;
    evaluationRequestsLast24Hours: number;
    latestRequestedAt: string | null;
  };
};

export type NotificationOutboxActionableItem = {
  outbox_event_id: string;
  event_type_code: string;
  source_event_key: string;
  entity_type_code: string;
  entity_id: string;
  occurred_at: string;
  status_code:
    | "PENDING"
    | "PROCESSING"
    | "FAILED_RETRYABLE"
    | "FAILED_FINAL";
  attempt_count: number;
  retry_budget_started_at_attempt: number;
  retry_cycle_attempt_count: number;
  available_at: string;
  locked_at: string | null;
  locked_by: string | null;
  completed_at: string | null;
  last_error_code: string | null;
  last_error_detail: Record<string, unknown>;
  correlation_id: string;
  created_at: string;
  can_retry: boolean;
  is_stale_processing: boolean;
};

export type NotificationAdminOperationResponse = {
  action:
    | "EVALUATION_REQUESTED"
    | "RETRY_REQUESTED"
    | "REPLAYED";
  originalAction?: string;
  adminOperationId: string;
  outboxEventId: string;
  eventTypeCode: string;
  evaluationFamilyCode?: NotificationEvaluationFamilyCode;
  previousStatusCode?: string;
  statusCode: string;
  attemptCount?: number;
  retryBudgetStartedAtAttempt?: number;
  retryCycleAttemptCount?: number;
  availableAt?: string;
  requestedAt: string;
  requestedByUserId: string;
  reason: string;
  correlationId: string;
  enqueueAction?: string;
};

export type StockReversalApplication = {
  reversal_application_id: string;
  organization_id: string;
  original_transaction_id: string;
  original_transaction_no: string;
  original_transaction_type_code: string;
  original_source_type_code: string;
  original_source_ref: string;
  reversal_transaction_id: string;
  reversal_transaction_no: string;
  original_entry_id: string;
  reversal_entry_id: string;
  product_id: string;
  batch_id: string;
  product_sku_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  bucket_code: string;
  original_quantity_delta: number;
  reversal_quantity_delta: number;
  quantity_applied: number;
  actor_user_id: string | null;
  process_name: string | null;
  note: string | null;
  created_at: string;
};

export type StockReversalPreviewBlocker = {
  code: string;
  message: string;
};

export type StockReversalPreviewLine = {
  originalEntryId: string;
  lineNo: number;
  productId: string;
  batchId: string;
  productSku: string;
  batchCode: string;
  expiryDate: string;
  bucketCode: string;
  originalDelta: number;
  quantityAlreadyReversed: number;
  quantityToReverse: number;
  reversalDelta: number;
  currentBatchBucketQty: number | null;
  resultingBatchBucketQty: number | null;
  currentProductSellableQty: number | null;
  currentProductQuarantineQty: number | null;
  currentProductDamagedQty: number | null;
  currentProductReservedQty: number | null;
  resultingProductSellableQty: number | null;
  resultingProductQuarantineQty: number | null;
  resultingProductDamagedQty: number | null;
  batchBalanceVersion: number | null;
  productPositionVersion: number | null;
};

export type StockReversalPreview = {
  status: "PREVIEW_READY" | "BLOCKED";
  eligible: boolean;
  basisHash: string;
  schemaVersion: number;
  originalTransaction: {
    transactionId: string;
    transactionNo: string;
    transactionTypeCode: string;
    reasonCode: string;
    channelCode: string;
    sourceTypeCode: string;
    sourceId: string | null;
    sourceRef: string;
    occurredAt: string;
    recordedAt: string;
    actorUserId: string | null;
    processName: string | null;
    note: string | null;
  };
  lineCount: number;
  totalAbsoluteQuantity: number;
  lines: StockReversalPreviewLine[];
  blockers: StockReversalPreviewBlocker[];
};

export type StockReversalMutationResponse = {
  status: "REVERSED";
  originalTransactionId: string;
  originalTransactionNo: string;
  originalTransactionType: string;
  reversalTransactionId: string;
  reversalTransactionNo: string;
  lineCount: number;
  totalAbsoluteQuantity: number;
  previewBasisHash: string;
  idempotencyKey: string;
  requestHash: string;
  recordedAt: string;
  actorUserId: string;
};

export type ManualOutboundLineInput = {
  productId: string;
  quantity: number;
  sourceLineRef: string;
};

export type ManualOutboundPreviewBlocker = {
  code: string;
  scope: "REQUEST" | "LINE" | string;
  message: string;
  lineNo?: number;
  productId?: string;
  productSku?: string | null;
  requestedQuantity?: number;
  sellableQuantity?: number;
  reservedQuantity?: number;
  availableQuantity?: number;
  eligibleQuantity?: number;
  shortageQuantity?: number;
};

export type ManualOutboundPreviewAllocation = {
  lineNo: number;
  sourceLineRef: string;
  allocationNo: number;
  productId: string;
  productSku: string;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  receivedFirstAt: string | null;
  currentBatchSellable: number;
  quantity: number;
  resultingBatchSellable: number;
  batchBalanceVersion: number;
};

export type ManualOutboundPreviewProduct = {
  lineNo: number;
  sourceLineRef: string;
  productId: string;
  productSku: string | null;
  productName: string | null;
  requestedQuantity: number;
  currentSellable: number;
  currentReserved: number;
  currentAvailable: number;
  eligibleFefoQuantity: number;
  allocatedQuantity: number;
  resultingSellable: number | null;
  resultingAvailable: number | null;
  status: "READY" | "BLOCKED";
  allocations: ManualOutboundPreviewAllocation[];
};

export type ManualOutboundPreview = {
  status: "PREVIEW_READY" | "BLOCKED";
  eligible: boolean;
  schemaVersion: number;
  basisHash: string;
  requestHash: string;
  organizationId: string;
  sourceRef: string;
  occurredAt: string;
  effectiveLocalDate: string;
  reasonCode: string;
  reasonName: string;
  channelCode: "MANUAL";
  note: string | null;
  reference: string | null;
  lineCount: number;
  totalRequestedQuantity: number;
  allocationCount: number;
  expirySafetyBufferDays: number;
  products: ManualOutboundPreviewProduct[];
  allocations: ManualOutboundPreviewAllocation[];
  blockers: ManualOutboundPreviewBlocker[];
};

export type ManualOutboundMutationAllocation = {
  lineNo: number;
  sourceLineRef: string;
  allocationNo: number;
  productId: string;
  productSku: string;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  quantity: number;
  ledgerSeq: number;
};

export type ManualOutboundMutationResponse = {
  status: "POSTED";
  outboundId: string;
  outboundNo: string;
  transactionId: string;
  transactionNo: string;
  idempotencyKey: string;
  requestHash: string;
  reasonCode: string;
  lineCount: number;
  allocationCount: number;
  totalQuantity: number;
  expirySafetyBufferDays: number;
  occurredAt: string;
  recordedAt: string;
  allocations: ManualOutboundMutationAllocation[];
};

export type ManualOutboundHeader = {
  outbound_id: string;
  organization_id: string;
  outbound_no: string;
  source_ref: string;
  reason_code_snapshot: string;
  status_code: string;
  occurred_at: string;
  recorded_at: string;
  actor_user_id: string | null;
  process_name: string | null;
  transaction_id: string;
  total_quantity: number;
  note: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type ManualOutboundLine = {
  outbound_line_id: string;
  organization_id: string;
  outbound_id: string;
  line_no: number;
  product_id: string;
  quantity_requested: number;
  product_sku_snapshot: string;
  source_line_ref: string;
  created_at: string;
};

export type ManualOutboundAllocation = {
  allocation_id: string;
  organization_id: string;
  outbound_id: string;
  outbound_line_id: string;
  allocation_no: number;
  ledger_entry_id: string;
  product_id: string;
  batch_id: string;
  quantity_allocated: number;
  product_sku_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  received_first_at_snapshot: string | null;
  source_line_ref: string;
  created_at: string;
};

export type ManualOutboundCommandInput = {
  sourceRef: string;
  occurredAt: string;
  reasonCode: string;
  lines: ManualOutboundLineInput[];
  note?: string | null;
  reference?: string | null;
  metadata?: Record<string, unknown>;
  organizationId?: string;
};

export type ManualOutboundData = {
  products: ProductInventory[];
  outbounds: ManualOutboundHeader[];
  selectedOutbound: ManualOutboundHeader | null;
  lines: ManualOutboundLine[];
  allocations: ManualOutboundAllocation[];
};


export type StockDisposalReasonCode =
  | "DAMAGED_DISPOSAL"
  | "EXPIRED_DISPOSAL";

export type StockDisposalBucketCode =
  | "SELLABLE"
  | "QUARANTINE"
  | "DAMAGED";

export type StockDisposalLineInput = {
  productId: string;
  batchId: string;
  sourceBucketCode: StockDisposalBucketCode;
  quantity: number;
  sourceLineRef: string;
};

export type StockDisposalPreviewBlocker = {
  code: string;
  scope: "REQUEST" | "LINE" | string;
  message: string;
  lineNo?: number;
};

export type StockDisposalPreviewLine = {
  lineNo: number;
  sourceLineRef: string;
  productId: string;
  productSku: string | null;
  productName: string | null;
  productActive: boolean | null;
  productRowVersion: number | null;
  batchId: string;
  batchCode: string | null;
  expiryDate: string | null;
  batchStatusCode: string | null;
  batchBlockReason: string | null;
  batchRowVersion: number | null;
  sourceBucketCode: StockDisposalBucketCode;
  quantityRequested: number;
  currentBatchSellableQty: number;
  currentBatchQuarantineQty: number;
  currentBatchDamagedQty: number;
  currentBatchBucketQty: number;
  resultingBatchBucketQty: number;
  batchBalanceVersion: number;
  batchLastLedgerSeq: number;
  currentProductSellableQty: number;
  currentProductQuarantineQty: number;
  currentProductDamagedQty: number;
  currentProductReservedQty: number;
  currentProductAvailableQty: number;
  currentProductOnHandQty: number;
  resultingProductSellableQty: number;
  resultingProductQuarantineQty: number;
  resultingProductDamagedQty: number;
  resultingProductAvailableQty: number;
  resultingProductOnHandQty: number;
  productPositionVersion: number;
  productLastLedgerSeq: number;
  lineEligible: boolean;
  blockers: StockDisposalPreviewBlocker[];
};

export type StockDisposalPreview = {
  status: "PREVIEW_READY" | "BLOCKED";
  eligible: boolean;
  schemaVersion: number;
  basisHash: string;
  requestHash: string;
  organizationId: string;
  organizationTimezone: string;
  sourceRef: string;
  occurredAt: string;
  effectiveLocalDate: string;
  reasonCode: StockDisposalReasonCode;
  reasonName: string;
  channelCode: "MANUAL";
  referenceText: string;
  note: string;
  lineCount: number;
  totalRequestedQuantity: number;
  lines: StockDisposalPreviewLine[];
  blockers: StockDisposalPreviewBlocker[];
};

export type StockDisposalMutationLine = {
  lineNo: number;
  disposalLineId: string;
  ledgerEntryId: string;
  ledgerSeq: number;
  productId: string;
  productSku: string;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  sourceBucketCode: StockDisposalBucketCode;
  quantity: number;
  bucketBeforeQty: number;
  bucketAfterQty: number;
  sourceLineRef: string;
};

export type StockDisposalMutationResponse = {
  status: "POSTED";
  disposalId: string;
  disposalNo: string;
  transactionId: string;
  transactionNo: string;
  idempotencyKey: string;
  requestHash: string;
  previewBasisHash: string;
  sourceRef: string;
  reasonCode: StockDisposalReasonCode;
  channelCode: "MANUAL";
  referenceText: string;
  lineCount: number;
  totalQuantity: number;
  occurredAt: string;
  recordedAt: string;
  lines: StockDisposalMutationLine[];
};

export type StockDisposalCandidate = {
  organization_id: string;
  product_id: string;
  product_sku: string;
  product_name: string;
  product_is_active: boolean;
  batch_id: string;
  batch_code: string;
  expiry_date: string;
  batch_status_code: "ACTIVE" | "BLOCKED" | "EXPIRED" | "ARCHIVED";
  block_reason: string | null;
  batch_row_version: number;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
  physical_qty: number;
  reserved_qty: number;
  local_date: string;
  is_expired: boolean;
  days_to_expiry: number;
  last_ledger_seq: number;
  balance_version: number;
};

export type StockDisposalHeader = {
  disposal_id: string;
  organization_id: string;
  disposal_no: string;
  source_ref: string;
  reason_code_snapshot: StockDisposalReasonCode;
  channel_code_snapshot: "MANUAL";
  status_code: "POSTED";
  occurred_at: string;
  recorded_at: string;
  actor_user_id: string | null;
  process_name: string | null;
  transaction_id: string;
  total_quantity: number;
  reference_text: string;
  note: string;
  request_hash: string;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type StockDisposalLine = {
  disposal_line_id: string;
  organization_id: string;
  disposal_id: string;
  line_no: number;
  product_id: string;
  batch_id: string;
  ledger_entry_id: string;
  source_bucket_code: StockDisposalBucketCode;
  quantity_disposed: number;
  product_sku_snapshot: string;
  product_name_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  batch_status_code_snapshot: string;
  source_line_ref: string;
  bucket_before_qty: number;
  bucket_after_qty: number;
  created_at: string;
};

export type StockDisposalCommandInput = {
  sourceRef: string;
  occurredAt: string;
  reasonCode: StockDisposalReasonCode;
  lines: StockDisposalLineInput[];
  referenceText: string;
  note: string;
  metadata?: Record<string, unknown>;
  organizationId?: string;
};

export type StockDisposalData = {
  candidates: StockDisposalCandidate[];
  disposals: StockDisposalHeader[];
  selectedDisposal: StockDisposalHeader | null;
  lines: StockDisposalLine[];
};

export type EntryCorrectionData = {
  ledger: StockLedgerEntry[];
  applications: StockReversalApplication[];
};
export type DashboardData = {
  products: ProductInventory[];
  batches: BatchInventory[];
  ledger: StockLedgerEntry[];
};

export type MarketplaceData = {
  orders: MarketplaceOrder[];
  reservations: MarketplaceReservation[];
  events: MarketplaceEvent[];
  allocations: MarketplaceShipAllocation[];
};
export type ReturnData = {
  returns: ReturnHeader[];
  items: ReturnItem[];
  events: ReturnEvent[];
  receiptLines: ReturnReceiptLine[];
  inspectionAllocations: ReturnInspectionAllocation[];
};

function getConfig() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(/\/$/, "");
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!publishableKey || publishableKey.includes("REPLACE_ME")) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum dikonfigurasi di .env.local.",
    );
  }

  return { url, publishableKey };
}

async function parseError(response: Response) {
  const raw = await response.text();

  if (!raw) {
    return `${response.status} ${response.statusText}`;
  }

  try {
    const parsed = JSON.parse(raw) as {
      message?: string;
      details?: string;
      hint?: string;
      code?: string;
    };

    return [parsed.message, parsed.details, parsed.hint, parsed.code]
      .filter(Boolean)
      .join(" | ");
  } catch {
    return raw;
  }
}

async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
  schema: "api" | "public" = "api",
): Promise<T> {
  const { url, publishableKey } = getConfig();
  const accessToken = await getAccessToken();

  if (!accessToken) {
    throw new Error("AUTH_SESSION_REQUIRED");
  }

  const headers = new Headers(init.headers);

  headers.set("apikey", publishableKey);
  headers.set("Authorization", `Bearer ${accessToken}`);
  headers.set("Accept-Profile", schema);

  if (init.body) {
    headers.set("Content-Type", "application/json");
    headers.set("Content-Profile", schema);
  }

  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers,
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(await parseError(response));
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

async function apiFetchAll<T>(
  path: string,
  pageSize = 500,
): Promise<T[]> {
  const rows: T[] = [];
  const separator = path.includes("?") ? "&" : "?";

  for (let offset = 0; ; offset += pageSize) {
    const page = await apiFetch<T[]>(
      `${path}${separator}limit=${pageSize}&offset=${offset}`,
    );

    rows.push(...page);

    if (page.length < pageSize) {
      return rows;
    }
  }
}

async function resolveOrganizationId(organizationId?: string) {
  if (organizationId) {
    return organizationId;
  }

  const session = await getAdminSession();

  if (!session) {
    throw new Error("AUTH_SESSION_REQUIRED");
  }

  return session.profile.organization_id;
}

export async function getDashboardData(
  organizationId?: string,
): Promise<DashboardData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [products, batches, ledger] = await Promise.all([
    apiFetch<ProductInventory[]>(
      `product_inventory?organization_id=eq.${encodedOrganizationId}&select=*&order=name.asc`,
    ),
    apiFetch<BatchInventory[]>(
      `batch_inventory?organization_id=eq.${encodedOrganizationId}&select=*&order=expiry_date.asc,batch_code.asc`,
    ),
    apiFetch<StockLedgerEntry[]>(
      `stock_ledger?organization_id=eq.${encodedOrganizationId}&select=*&order=ledger_seq.desc&limit=20`,
    ),
  ]);

  return { products, batches, ledger };
}

function manualOutboundMetadata(input: ManualOutboundCommandInput) {
  const metadata = { ...(input.metadata ?? {}) };

  if (input.reference) {
    metadata.reference = input.reference;
  } else {
    delete metadata.reference;
  }

  return metadata;
}

export async function previewManualOutbound(
  input: ManualOutboundCommandInput,
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<ManualOutboundPreview>("preview_manual_outbound", {
    p_organization_id: resolvedOrganizationId,
    p_source_ref: input.sourceRef,
    p_occurred_at: input.occurredAt,
    p_reason_code: input.reasonCode,
    p_lines: input.lines,
    p_note: input.note ?? null,
    p_metadata: manualOutboundMetadata(input),
  });
}

export async function postManualOutbound(
  input: ManualOutboundCommandInput & {
    idempotencyKey: string;
    previewBasisHash: string;
    confirmation: boolean;
  },
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<ManualOutboundMutationResponse>("post_manual_outbound", {
    p_organization_id: resolvedOrganizationId,
    p_idempotency_key: input.idempotencyKey,
    p_source_ref: input.sourceRef,
    p_occurred_at: input.occurredAt,
    p_reason_code: input.reasonCode,
    p_lines: input.lines,
    p_preview_basis_hash: input.previewBasisHash,
    p_confirmation: input.confirmation,
    p_note: input.note ?? null,
    p_metadata: manualOutboundMetadata(input),
  });
}

export async function getManualOutboundData(
  organizationId?: string,
  selectedOutboundId?: string,
): Promise<ManualOutboundData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);
  const normalizedSelectedOutboundId = selectedOutboundId?.trim() ?? "";
  const selectedOutboundIsValid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      normalizedSelectedOutboundId,
    );
  const encodedSelectedOutboundId = encodeURIComponent(
    normalizedSelectedOutboundId,
  );

  const selectedOutboundPromise = selectedOutboundIsValid
    ? apiFetch<ManualOutboundHeader[]>(
        `manual_outbounds?organization_id=eq.${encodedOrganizationId}&outbound_id=eq.${encodedSelectedOutboundId}&select=*&limit=1`,
      )
    : Promise.resolve([]);
  const selectedLinesPromise = selectedOutboundIsValid
    ? apiFetchAll<ManualOutboundLine>(
        `manual_outbound_lines?organization_id=eq.${encodedOrganizationId}&outbound_id=eq.${encodedSelectedOutboundId}&select=*&order=line_no.asc`,
      )
    : Promise.resolve([]);
  const selectedAllocationsPromise = selectedOutboundIsValid
    ? apiFetchAll<ManualOutboundAllocation>(
        `manual_outbound_allocations?organization_id=eq.${encodedOrganizationId}&outbound_id=eq.${encodedSelectedOutboundId}&select=*&order=outbound_line_id.asc,allocation_no.asc`,
      )
    : Promise.resolve([]);

  const [
    products,
    recentOutbounds,
    selectedOutboundRows,
    lines,
    allocations,
  ] = await Promise.all([
    apiFetch<ProductInventory[]>(
      `product_inventory?organization_id=eq.${encodedOrganizationId}&is_active=eq.true&select=*&order=name.asc`,
    ),
    apiFetch<ManualOutboundHeader[]>(
      `manual_outbounds?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=50`,
    ),
    selectedOutboundPromise,
    selectedLinesPromise,
    selectedAllocationsPromise,
  ]);

  const selectedOutbound = selectedOutboundRows[0] ?? null;
  const outboundById = new Map(
    [...recentOutbounds, ...selectedOutboundRows].map((outbound) => [
      outbound.outbound_id,
      outbound,
    ]),
  );

  return {
    products,
    outbounds: [...outboundById.values()].sort(
      (left, right) =>
        new Date(right.occurred_at).getTime() -
        new Date(left.occurred_at).getTime(),
    ),
    selectedOutbound,
    lines,
    allocations,
  };
}


export async function previewStockDisposal(
  input: StockDisposalCommandInput,
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<StockDisposalPreview>("preview_stock_disposal", {
    p_organization_id: resolvedOrganizationId,
    p_source_ref: input.sourceRef,
    p_occurred_at: input.occurredAt,
    p_reason_code: input.reasonCode,
    p_lines: input.lines,
    p_reference_text: input.referenceText,
    p_note: input.note,
    p_metadata: input.metadata ?? {},
  });
}

export async function postStockDisposal(
  input: StockDisposalCommandInput & {
    idempotencyKey: string;
    previewBasisHash: string;
    confirmation: boolean;
  },
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<StockDisposalMutationResponse>("post_stock_disposal", {
    p_organization_id: resolvedOrganizationId,
    p_idempotency_key: input.idempotencyKey,
    p_source_ref: input.sourceRef,
    p_occurred_at: input.occurredAt,
    p_reason_code: input.reasonCode,
    p_lines: input.lines,
    p_preview_basis_hash: input.previewBasisHash,
    p_confirmation: input.confirmation,
    p_reference_text: input.referenceText,
    p_note: input.note,
    p_metadata: input.metadata ?? {},
  });
}

export async function getStockDisposalData(
  organizationId?: string,
  selectedDisposalId?: string,
): Promise<StockDisposalData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);
  const normalizedSelectedDisposalId = selectedDisposalId?.trim() ?? "";
  const selectedDisposalIsValid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      normalizedSelectedDisposalId,
    );
  const encodedSelectedDisposalId = encodeURIComponent(
    normalizedSelectedDisposalId,
  );

  const selectedDisposalPromise = selectedDisposalIsValid
    ? apiFetch<StockDisposalHeader[]>(
        `stock_disposals?organization_id=eq.${encodedOrganizationId}&disposal_id=eq.${encodedSelectedDisposalId}&select=*&limit=1`,
      )
    : Promise.resolve([]);
  const selectedLinesPromise = selectedDisposalIsValid
    ? apiFetchAll<StockDisposalLine>(
        `stock_disposal_lines?organization_id=eq.${encodedOrganizationId}&disposal_id=eq.${encodedSelectedDisposalId}&select=*&order=line_no.asc`,
      )
    : Promise.resolve([]);

  const [candidates, recentDisposals, selectedDisposalRows, lines] =
    await Promise.all([
      apiFetchAll<StockDisposalCandidate>(
        `stock_disposal_candidates?organization_id=eq.${encodedOrganizationId}&select=*&order=is_expired.desc,days_to_expiry.asc,batch_code.asc`,
      ),
      apiFetch<StockDisposalHeader[]>(
        `stock_disposals?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=50`,
      ),
      selectedDisposalPromise,
      selectedLinesPromise,
    ]);

  const selectedDisposal = selectedDisposalRows[0] ?? null;
  const disposalById = new Map(
    [...recentDisposals, ...selectedDisposalRows].map((disposal) => [
      disposal.disposal_id,
      disposal,
    ]),
  );

  return {
    candidates,
    disposals: [...disposalById.values()].sort(
      (left, right) =>
        new Date(right.occurred_at).getTime() -
        new Date(left.occurred_at).getTime(),
    ),
    selectedDisposal,
    lines,
  };
}

export async function getEntryCorrectionData(
  organizationId?: string,
  selectedTransactionId?: string,
): Promise<EntryCorrectionData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);
  const normalizedSelectedTransactionId =
    selectedTransactionId?.trim() ?? "";
  const selectedTransactionIsValid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      normalizedSelectedTransactionId,
    );
  const encodedSelectedTransactionId = encodeURIComponent(
    normalizedSelectedTransactionId,
  );

  const selectedLedgerPromise = selectedTransactionIsValid
    ? apiFetchAll<StockLedgerEntry>(
        `stock_ledger?organization_id=eq.${encodedOrganizationId}&transaction_id=eq.${encodedSelectedTransactionId}&select=*&order=line_no.asc,ledger_seq.asc`,
      )
    : Promise.resolve([]);
  const selectedApplicationsPromise = selectedTransactionIsValid
    ? apiFetchAll<StockReversalApplication>(
        `stock_reversal_applications?organization_id=eq.${encodedOrganizationId}&or=(original_transaction_id.eq.${encodedSelectedTransactionId},reversal_transaction_id.eq.${encodedSelectedTransactionId})&select=*&order=created_at.asc`,
      )
    : Promise.resolve([]);

  const [
    recentLedger,
    recentApplications,
    selectedLedger,
    selectedApplications,
  ] = await Promise.all([
    apiFetch<StockLedgerEntry[]>(
      `stock_ledger?organization_id=eq.${encodedOrganizationId}&select=*&order=ledger_seq.desc&limit=1000`,
    ),
    apiFetch<StockReversalApplication[]>(
      `stock_reversal_applications?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc&limit=1000`,
    ),
    selectedLedgerPromise,
    selectedApplicationsPromise,
  ]);

  const ledgerById = new Map(
    [...recentLedger, ...selectedLedger].map((entry) => [
      entry.ledger_entry_id,
      entry,
    ]),
  );
  const applicationById = new Map(
    [...recentApplications, ...selectedApplications].map((application) => [
      application.reversal_application_id,
      application,
    ]),
  );

  return {
    ledger: [...ledgerById.values()].filter((entry) =>
      ["RECEIPT", "MANUAL_OUTBOUND", "DISPOSAL", "REVERSAL"].includes(
        entry.transaction_type_code,
      ),
    ),
    applications: [...applicationById.values()],
  };
}

export async function previewStockTransactionReversal(
  originalTransactionId: string,
  organizationId?: string,
) {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);

  return callRpc<StockReversalPreview>("preview_stock_transaction_reversal", {
    p_organization_id: resolvedOrganizationId,
    p_original_transaction_id: originalTransactionId,
  });
}

export async function reverseStockTransaction(input: {
  originalTransactionId: string;
  previewBasisHash: string;
  idempotencyKey: string;
  confirmation: boolean;
  note: string;
  metadata?: Record<string, unknown>;
  organizationId?: string;
}) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<StockReversalMutationResponse>("reverse_stock_transaction", {
    p_organization_id: resolvedOrganizationId,
    p_idempotency_key: input.idempotencyKey,
    p_original_transaction_id: input.originalTransactionId,
    p_preview_basis_hash: input.previewBasisHash,
    p_confirmation: input.confirmation,
    p_note: input.note,
    p_metadata: input.metadata ?? {},
  });
}
export async function getMarketplaceData(
  organizationId?: string,
): Promise<MarketplaceData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [orders, reservations, events, allocations] = await Promise.all([
    apiFetch<MarketplaceOrder[]>(
      `marketplace_orders?organization_id=eq.${encodedOrganizationId}&select=*&order=reserved_at.desc&limit=50`,
    ),
    apiFetch<MarketplaceReservation[]>(
      `marketplace_reservations?organization_id=eq.${encodedOrganizationId}&select=*&order=reserved_at.desc,line_no.asc&limit=100`,
    ),
    apiFetch<MarketplaceEvent[]>(
      `marketplace_events?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=100`,
    ),
    apiFetch<MarketplaceShipAllocation[]>(
      `marketplace_ship_allocations?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc&limit=100`,
    ),
  ]);

  return { orders, reservations, events, allocations };
}

export async function getReturnData(
  organizationId?: string,
): Promise<ReturnData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [returns, items, events, receiptLines, inspectionAllocations] =
    await Promise.all([
      apiFetch<ReturnHeader[]>(
        `returns?organization_id=eq.${encodedOrganizationId}&select=*&order=expected_at.desc&limit=100`,
      ),
      apiFetch<ReturnItem[]>(
        `return_items?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc,line_no.asc&limit=200`,
      ),
      apiFetch<ReturnEvent[]>(
        `return_events?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=200`,
      ),
      apiFetch<ReturnReceiptLine[]>(
        `return_receipt_lines?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc,line_no.asc&limit=200`,
      ),
      apiFetch<ReturnInspectionAllocation[]>(
        `return_inspection_allocations?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc,allocation_no.asc&limit=200`,
      ),
    ]);

  return {
    returns,
    items,
    events,
    receiptLines,
    inspectionAllocations,
  };
}
export async function getReconciliationData(
  organizationId?: string,
): Promise<ReconciliationData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [runs, checks, issues, evidence] = await Promise.all([
    apiFetch<ReconciliationRun[]>(
      `reconciliation_runs?organization_id=eq.${encodedOrganizationId}&select=*&order=started_at.desc&limit=50`,
    ),
    apiFetch<ReconciliationCheck[]>(
      `reconciliation_checks?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc&limit=200`,
    ),
    apiFetch<ReconciliationIssue[]>(
      `reconciliation_issues?organization_id=eq.${encodedOrganizationId}&select=*&order=last_seen_at.desc&limit=200`,
    ),
    apiFetch<ReconciliationIssueEvidence[]>(
      `reconciliation_issue_evidence?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc,evidence_no.asc&limit=500`,
    ),
  ]);

  return { runs, checks, issues, evidence };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function getReconciliationRunData(
  runId: string,
  organizationId?: string,
): Promise<{
  run: ReconciliationRun | null;
  checks: ReconciliationCheck[];
}> {
  const normalizedRunId = runId.trim();

  if (!UUID_PATTERN.test(normalizedRunId)) {
    return { run: null, checks: [] };
  }

  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);
  const encodedRunId = encodeURIComponent(normalizedRunId);

  const runs = await apiFetch<ReconciliationRun[]>(
    `reconciliation_runs?organization_id=eq.${encodedOrganizationId}&run_id=eq.${encodedRunId}&select=*&limit=1`,
  );
  const run = runs[0] ?? null;

  if (!run) {
    return { run: null, checks: [] };
  }

  const checks = await apiFetch<ReconciliationCheck[]>(
    `reconciliation_checks?organization_id=eq.${encodedOrganizationId}&run_id=eq.${encodedRunId}&select=*&order=check_code.asc`,
  );

  return { run, checks };
}
export async function getNotificationList(
  filters: NotificationListFilters = {},
) {
  return callRpc<NotificationListItem[]>("notification_list", {
    p_lifecycle_status_code: filters.lifecycleStatusCode ?? null,
    p_severity_code: filters.severityCode ?? null,
    p_category_code: filters.categoryCode ?? null,
    p_read_state_code: filters.readStateCode ?? null,
    p_include_archived: filters.includeArchived ?? false,
    p_limit: filters.limit ?? 50,
    p_before_last_seen_at: filters.beforeLastSeenAt ?? null,
    p_before_id: filters.beforeId ?? null,
  });
}

export async function getNotificationDetail(notificationId: string) {
  const normalizedNotificationId = notificationId.trim();

  if (!UUID_PATTERN.test(normalizedNotificationId)) {
    return null;
  }

  const rows = await callRpc<NotificationDetail[]>("notification_detail", {
    p_notification_id: normalizedNotificationId,
  });

  return rows[0] ?? null;
}

export async function getNotificationEventHistory(
  notificationId: string,
  limit = 100,
) {
  const normalizedNotificationId = notificationId.trim();

  if (!UUID_PATTERN.test(normalizedNotificationId)) {
    return [];
  }

  return callRpc<NotificationEventHistoryItem[]>(
    "notification_event_history",
    {
      p_notification_id: normalizedNotificationId,
      p_limit: limit,
      p_after_occurred_at: null,
      p_after_id: null,
    },
  );
}

export async function setNotificationReadState(
  notificationId: string,
  readStateCode: NotificationReadStateCode,
) {
  return callRpc<NotificationReadStateMutationResponse>(
    "set_notification_read_state",
    {
      p_notification_id: notificationId,
      p_read_state_code: readStateCode,
    },
  );
}

export async function acknowledgeNotification(
  notificationId: string,
  note: string | null = null,
) {
  return callRpc<NotificationLifecycleMutationResponse>(
    "acknowledge_notification",
    {
      p_notification_id: notificationId,
      p_note: note,
    },
  );
}

export async function revokeNotificationAcknowledgment(
  notificationId: string,
  note: string | null = null,
) {
  return callRpc<NotificationLifecycleMutationResponse>(
    "revoke_notification_acknowledgment",
    {
      p_notification_id: notificationId,
      p_note: note,
    },
  );
}


export async function getNotificationOperationsSummary() {
  return callRpc<NotificationOperationsSummary>(
    "get_notification_operations_summary",
    {},
  );
}

export async function getNotificationOutboxActionableList(
  statusCode: string | null = null,
  limit = 50,
) {
  return callRpc<NotificationOutboxActionableItem[]>(
    "notification_outbox_actionable_list",
    {
      p_status_code: statusCode,
      p_limit: limit,
    },
  );
}

export async function runNotificationEvaluation(
  evaluationFamilyCode: NotificationEvaluationFamilyCode,
  reason: string,
  idempotencyKey: string,
) {
  return callRpc<NotificationAdminOperationResponse>(
    "run_notification_evaluation",
    {
      p_evaluation_family_code: evaluationFamilyCode,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
    },
  );
}

export async function retryNotificationOutboxEvent(
  outboxEventId: string,
  reason: string,
  idempotencyKey: string,
) {
  return callRpc<NotificationAdminOperationResponse>(
    "retry_notification_outbox_event",
    {
      p_outbox_event_id: outboxEventId,
      p_reason: reason,
      p_idempotency_key: idempotencyKey,
    },
  );
}

export async function getNotificationUnreadCount() {
  const value = await callRpc<number | string>(
    "notification_unread_count",
    {},
  );
  const normalized = typeof value === "number" ? value : Number(value);

  return Number.isFinite(normalized) ? normalized : 0;
}

export async function callRpc<T>(name: string, body: Record<string, unknown>) {
  return apiFetch<T>(`rpc/${name}`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}
