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
  pre_shipment_cancelled_qty: number;
  post_shipment_cancelled_qty: number;
  return_expected_qty: number;
  remaining_post_cancellable_qty: number;
  total_remaining_cancellable_qty: number;
  cancellation_status_code:
    | "NONE"
    | "PRE_SHIPMENT"
    | "POST_SHIPMENT"
    | "MIXED";
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
  pre_shipment_cancelled_qty: number;
  post_shipment_cancelled_qty: number;
  return_expected_qty: number;
  remaining_post_cancellable_qty: number;
  total_remaining_cancellable_qty: number;
  cancellation_status_code:
    | "NONE"
    | "PRE_SHIPMENT"
    | "POST_SHIPMENT"
    | "MIXED";
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

export type MarketplaceCancellationPhaseCode =
  | "PRE_SHIPMENT"
  | "POST_SHIPMENT";

export type MarketplaceCancellationEffectCode =
  | "PRE_SHIPMENT_RELEASE"
  | "POST_SHIPMENT_REVERSAL";

export type MarketplaceCancellationStatusCode = "POSTED";

export type MarketplaceCancellationLineInput = {
  productId: string;
  orderItemRef: string;
  phaseCode: MarketplaceCancellationPhaseCode;
  quantity: number;
  sourceLineRef: string;
};

export type MarketplaceCancellationCommandInput = {
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  eventRef: string;
  orderRef: string;
  occurredAt: string;
  sourceStatus: string;
  lines: MarketplaceCancellationLineInput[];
  note?: string | null;
  metadata?: Record<string, unknown>;
  organizationId?: string;
};

export type MarketplaceCancellationPreviewBlocker = {
  code: string;
  scope: "REQUEST" | "LINE" | string;
  message: string;
  lineNo?: number;
};

export type MarketplaceCancellationPreviewApplication = {
  applicationNo: number;
  effectCode: MarketplaceCancellationEffectCode;
  quantity: number;
  reservationId: string;
  shipAllocationId?: string;
  shipAllocationNo?: number;
  shipEventId?: string;
  shipEventRef?: string;
  originalTransactionId?: string;
  originalTransactionNo?: string;
  originalLedgerEntryId?: string;
  originalLedgerSeq?: number;
  productId?: string;
  productSku?: string;
  batchId?: string;
  batchCode?: string;
  expiryDate?: string;
  bucketCode?: "SELLABLE";
  allocationQuantity?: number;
  alreadyReversedQuantity?: number;
  remainingBeforeQuantity?: number;
  batchSellableBefore?: number;
  batchSellableAfter?: number;
  batchBalanceVersion?: number;
};

export type MarketplaceCancellationPreviewLine = {
  lineNo: number;
  productId: string;
  productSku: string | null;
  orderItemId: string | null;
  orderItemRef: string;
  reservationId: string | null;
  phaseCode: MarketplaceCancellationPhaseCode;
  quantity: number;
  sourceLineRef: string;
  reservedQuantity: number;
  shippedQuantity: number;
  releasedQuantity: number;
  openReservedBefore: number;
  openReservedAfter: number;
  preShipmentCancelledBefore: number;
  preShipmentCancelledAfter: number;
  postShipmentCancelledBefore: number;
  postShipmentCancelledAfter: number;
  returnExpectedQuantity: number;
  remainingPostCancellableBefore: number;
  remainingPostCancellableAfter: number;
  productSellableBefore: number;
  productSellableAfter: number;
  productReservedBefore: number;
  productReservedAfter: number;
  productPositionVersion: number;
  applications: MarketplaceCancellationPreviewApplication[];
  eligible: boolean;
  blockers: MarketplaceCancellationPreviewBlocker[];
};

export type MarketplaceCancellationPreview = {
  eligible: boolean;
  blockers: MarketplaceCancellationPreviewBlocker[];
  requestHash: string;
  basisHash: string;
  organizationId: string;
  organizationTimezone: string;
  effectiveLocalDate: string;
  channelId: string;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  eventRef: string;
  orderId: string | null;
  orderRef: string;
  orderStatus: string | null;
  orderReservedAt: string | null;
  sourceStatus: string;
  occurredAt: string;
  sourceAlreadyPosted: boolean;
  totalRequestedQuantity: number;
  preShipmentQuantity: number;
  postShipmentQuantity: number;
  note: string | null;
  metadata: Record<string, unknown>;
  lines: MarketplaceCancellationPreviewLine[];
};

export type MarketplaceCancellationMutationLine = {
  cancellationLineId: string;
  eventLineId: string;
  lineNo: number;
  orderItemId: string;
  orderItemRef: string;
  productId: string;
  productSku: string;
  phaseCode: MarketplaceCancellationPhaseCode;
  quantity: number;
  sourceLineRef: string;
};

export type MarketplaceCancellationReversalTransaction = {
  originalTransactionId: string;
  originalTransactionNo: string;
  reversalTransactionId: string;
  reversalTransactionNo: string;
  applicationCount: number;
  totalQuantity: number;
};

export type MarketplaceCancellationMutationResponse = {
  status: "POSTED";
  cancellationId: string;
  cancellationNo: string;
  eventId: string;
  eventRef: string;
  orderId: string;
  orderRef: string;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  sourceStatus: string;
  totalQuantity: number;
  preShipmentQuantity: number;
  postShipmentQuantity: number;
  lineCount: number;
  reversalTransactionCount: number;
  singleReversalTransactionId: string | null;
  occurredAt: string;
  recordedAt: string;
  requestHash: string;
  previewBasisHash: string;
  lines: MarketplaceCancellationMutationLine[];
  reversalTransactions: MarketplaceCancellationReversalTransaction[];
};

export type MarketplaceCancellationCandidate = {
  organization_id: string;
  order_id: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  external_order_ref: string;
  order_status_code: string;
  order_item_id: string;
  line_no: number;
  external_item_ref: string;
  product_id: string;
  product_sku_snapshot: string;
  quantity_ordered: number;
  reservation_id: string;
  reserved_qty: number;
  shipped_qty: number;
  released_qty: number;
  open_reserved_qty: number;
  pre_shipment_cancelled_qty: number;
  post_shipment_cancelled_qty: number;
  return_expected_qty: number;
  return_received_qty: number;
  return_sellable_qty: number;
  return_damaged_qty: number;
  return_lost_qty: number;
  remaining_post_cancellable_qty: number;
  total_remaining_cancellable_qty: number;
  cancellation_status_code: "NONE" | "PRE_SHIPMENT" | "POST_SHIPMENT" | "MIXED";
  reservation_status_code: string;
  reserved_at: string;
  closed_at: string | null;
};

export type MarketplaceCancellationHeader = {
  cancellation_id: string;
  organization_id: string;
  cancellation_no: string;
  event_id: string;
  order_id: string;
  channel_id: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  external_order_ref: string;
  external_event_ref: string;
  source_status_code: string;
  status_code: MarketplaceCancellationStatusCode;
  occurred_at: string;
  recorded_at: string;
  actor_user_id: string | null;
  process_name: string | null;
  total_quantity: number;
  pre_shipment_quantity: number;
  post_shipment_quantity: number;
  request_hash: string;
  note: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type MarketplaceCancellationLine = {
  cancellation_line_id: string;
  organization_id: string;
  cancellation_id: string;
  cancellation_no: string;
  external_event_ref: string;
  event_line_id: string;
  line_no: number;
  order_item_id: string;
  reservation_id: string;
  product_id: string;
  phase_code: MarketplaceCancellationPhaseCode;
  quantity_cancelled: number;
  product_sku_snapshot: string;
  order_item_ref_snapshot: string;
  source_line_ref: string;
  open_reserved_before: number;
  open_reserved_after: number;
  shipped_before: number;
  return_expected_before: number;
  post_cancelled_before: number;
  post_cancelled_after: number;
  created_at: string;
};

export type MarketplaceCancellationApplication = {
  cancellation_application_id: string;
  organization_id: string;
  cancellation_line_id: string;
  cancellation_id: string;
  cancellation_no: string;
  external_event_ref: string;
  application_no: number;
  effect_code: MarketplaceCancellationEffectCode;
  quantity_applied: number;
  reservation_id: string;
  marketplace_ship_allocation_id: string | null;
  original_ship_event_id: string | null;
  original_ship_event_ref: string | null;
  original_ledger_entry_id: string | null;
  stock_reversal_application_id: string | null;
  original_transaction_id: string | null;
  original_transaction_no: string | null;
  reversal_transaction_id: string | null;
  reversal_transaction_no: string | null;
  reversal_entry_id: string | null;
  product_id: string | null;
  batch_id: string | null;
  product_sku_snapshot: string | null;
  batch_code_snapshot: string | null;
  expiry_date_snapshot: string | null;
  created_at: string;
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
  candidates: MarketplaceCancellationCandidate[];
  events: MarketplaceEvent[];
  allocations: MarketplaceShipAllocation[];
  cancellations: MarketplaceCancellationHeader[];
  cancellationLines: MarketplaceCancellationLine[];
  cancellationApplications: MarketplaceCancellationApplication[];
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
export async function previewMarketplaceCancellation(
  input: MarketplaceCancellationCommandInput,
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<MarketplaceCancellationPreview>(
    "preview_marketplace_cancellation",
    {
      p_organization_id: resolvedOrganizationId,
      p_channel_code: input.channelCode,
      p_event_ref: input.eventRef,
      p_order_ref: input.orderRef,
      p_occurred_at: input.occurredAt,
      p_source_status: input.sourceStatus,
      p_lines: input.lines,
      p_note: input.note ?? null,
      p_metadata: input.metadata ?? {},
    },
  );
}

export async function postMarketplaceCancellation(
  input: MarketplaceCancellationCommandInput & {
    idempotencyKey: string;
    previewBasisHash: string;
    confirmation: boolean;
  },
) {
  const resolvedOrganizationId = await resolveOrganizationId(
    input.organizationId,
  );

  return callRpc<MarketplaceCancellationMutationResponse>(
    "post_marketplace_cancellation",
    {
      p_organization_id: resolvedOrganizationId,
      p_idempotency_key: input.idempotencyKey,
      p_channel_code: input.channelCode,
      p_event_ref: input.eventRef,
      p_order_ref: input.orderRef,
      p_occurred_at: input.occurredAt,
      p_source_status: input.sourceStatus,
      p_lines: input.lines,
      p_preview_basis_hash: input.previewBasisHash,
      p_confirmation: input.confirmation,
      p_note: input.note ?? null,
      p_metadata: input.metadata ?? {},
    },
  );
}
export async function getMarketplaceData(
  organizationId?: string,
): Promise<MarketplaceData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [
    orders,
    reservations,
    candidates,
    events,
    allocations,
    cancellations,
    cancellationLines,
    cancellationApplications,
  ] = await Promise.all([
    apiFetch<MarketplaceOrder[]>(
      `marketplace_orders?organization_id=eq.${encodedOrganizationId}&select=*&order=reserved_at.desc&limit=50`,
    ),
    apiFetch<MarketplaceReservation[]>(
      `marketplace_reservations?organization_id=eq.${encodedOrganizationId}&select=*&order=reserved_at.desc,line_no.asc&limit=200`,
    ),
    apiFetch<MarketplaceCancellationCandidate[]>(
      `marketplace_cancellation_candidates?organization_id=eq.${encodedOrganizationId}&select=*&order=reserved_at.desc,line_no.asc&limit=200`,
    ),
    apiFetch<MarketplaceEvent[]>(
      `marketplace_events?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=200`,
    ),
    apiFetch<MarketplaceShipAllocation[]>(
      `marketplace_ship_allocations?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc&limit=200`,
    ),
    apiFetch<MarketplaceCancellationHeader[]>(
      `marketplace_cancellations?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=100`,
    ),
    apiFetch<MarketplaceCancellationLine[]>(
      `marketplace_cancellation_lines?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc,line_no.asc&limit=300`,
    ),
    apiFetch<MarketplaceCancellationApplication[]>(
      `marketplace_cancellation_applications?organization_id=eq.${encodedOrganizationId}&select=*&order=created_at.desc,application_no.asc&limit=500`,
    ),
  ]);

  return {
    orders,
    reservations,
    candidates,
    events,
    allocations,
    cancellations,
    cancellationLines,
    cancellationApplications,
  };
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

// OPENING_BALANCE_ADMIN_WORKFLOW_START
export type OpeningBalanceVerificationStatus =
  | "PENDING_POST"
  | "NOT_APPLICABLE"
  | "UNVERIFIED"
  | "PARTIALLY_VERIFIED"
  | "VERIFIED";

export type OpeningBalanceOperationalStatus =
  | "DRAFT"
  | "REVIEW"
  | "ACTIVE"
  | "POSTED_INACTIVE"
  | "REVERSED";

export type OpeningBalanceCutover = {
  cutover_id: string;
  organization_id: string;
  cutover_no: string;
  source_ref: string;
  source_estimate_ref: string;
  status_code: "DRAFT" | "REVIEW" | "POSTED";
  cutover_at: string;
  effective_local_date: string;
  created_at: string;
  updated_at: string;
  created_by: string | null;
  create_process_name: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  review_process_name: string | null;
  posted_at: string | null;
  posted_by: string | null;
  post_process_name: string | null;
  transaction_id: string | null;
  request_hash: string | null;
  posted_basis_hash: string | null;
  ledger_seq_before: number | null;
  ledger_seq_after: number | null;
  line_count: number;
  positive_line_count: number;
  total_quantity: number;
  note: string;
  metadata: Record<string, unknown>;
  row_version: number;
  verification_status_code: OpeningBalanceVerificationStatus;
  verified_line_count: number;
  unverified_line_count: number;
  operational_status_code: OpeningBalanceOperationalStatus;
  is_active: boolean;
  reversal_record_id: string | null;
  reversal_transaction_id: string | null;
  reversed_at: string | null;
  reversed_by: string | null;
  reversal_process_name: string | null;
  reversal_note: string | null;
  reversal_ledger_seq_before: number | null;
  reversal_ledger_seq_after: number | null;
};

export type OpeningBalanceCutoverLine = {
  opening_balance_line_id: string;
  organization_id: string;
  cutover_id: string;
  line_no: number;
  product_id: string;
  batch_id: string;
  bucket_code: "SELLABLE" | "QUARANTINE" | "DAMAGED";
  quantity: number;
  batch_identity_verified: boolean;
  exception_reference: string | null;
  product_sku_snapshot: string;
  product_name_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  batch_status_code_snapshot: string;
  product_row_version_snapshot: number;
  batch_row_version_snapshot: number;
  source_line_ref: string;
  ledger_entry_id: string | null;
  batch_bucket_qty_before: number | null;
  batch_bucket_qty_after: number | null;
  product_bucket_qty_before: number | null;
  product_bucket_qty_after: number | null;
  created_at: string;
  updated_at: string;
  verification_status_code: OpeningBalanceVerificationStatus;
  verification_application_id: string | null;
  verifying_stocktake_id: string | null;
  verifying_stocktake_approval_id: string | null;
  verifying_approval_version_no: number | null;
  verifying_stocktake_posting_id: string | null;
  verifying_stocktake_posting_line_id: string | null;
  verifying_stocktake_line_id: string | null;
  verifying_count_attempt_id: string | null;
  verifying_physical_quantity: number | null;
  verifying_variance_quantity: number | null;
  verified_at: string | null;
  verifying_counted_at: string | null;
  verifying_adjustment_ledger_entry_id: string | null;
  verifying_stocktake_no: string | null;
  cutover_operational_status_code: OpeningBalanceOperationalStatus;
  reversal_record_id: string | null;
  reversal_transaction_id: string | null;
  reversed_at: string | null;
};

export type OpeningBalanceDraftLineInput = {
  productId: string;
  batchId: string;
  bucketCode: "SELLABLE" | "QUARANTINE" | "DAMAGED";
  quantity: number;
  batchIdentityVerified: boolean;
  exceptionReference: string | null;
  sourceLineRef: string;
};

export type OpeningBalancePreviewBlocker = {
  code: string;
  scope: string;
  lineNo?: number;
  message: string;
};

export type OpeningBalancePreviewLine = {
  lineNo: number;
  openingBalanceLineId: string;
  productId: string;
  productSku: string;
  productName: string;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  batchStatusCode: string;
  bucketCode: "SELLABLE" | "QUARANTINE" | "DAMAGED";
  quantity: number;
  batchIdentityVerified: boolean;
  exceptionReference: string | null;
  sourceLineRef: string;
  currentBatchBucketQty: number;
  resultingBatchBucketQty: number;
  currentProductBucketQty: number;
  resultingProductBucketQty: number;
  reservedQty: number;
  verificationStatusCode: OpeningBalanceVerificationStatus;
};

export type OpeningBalancePreview = {
  status: "PREVIEW_READY" | "BLOCKED";
  eligible: boolean;
  schemaVersion: number;
  organizationId: string;
  cutoverId: string;
  cutoverNo: string;
  sourceRef: string;
  sourceEstimateRef: string;
  cutoverAt: string;
  effectiveLocalDate: string;
  requestHash: string;
  basisHash: string;
  lineCount: number;
  positiveLineCount: number;
  totalQuantity: number;
  note: string;
  metadata: Record<string, unknown>;
  lines: OpeningBalancePreviewLine[];
  blockers: OpeningBalancePreviewBlocker[];
};

export type OpeningBalanceCreateResponse = {
  status: "DRAFT";
  cutoverId: string;
  cutoverNo: string;
  sourceRef: string;
  cutoverAt: string;
  effectiveLocalDate: string;
  rowVersion: number;
};

export type OpeningBalanceSaveResponse = {
  status: "DRAFT";
  cutoverId: string;
  rowVersion: number;
  lineCount: number;
  positiveLineCount: number;
  totalQuantity: number;
  effectiveLocalDate: string;
};

export type OpeningBalanceReviewResponse = {
  status: "REVIEW";
  cutoverId: string;
  requestHash: string;
  rowVersion: number;
  lineCount: number;
  positiveLineCount: number;
  totalQuantity: number;
};

export type OpeningBalancePostResponse = {
  status: "POSTED";
  cutoverId: string;
  cutoverNo: string;
  transactionId: string;
  transactionNo: string;
  idempotencyKey: string;
  requestHash: string;
  previewBasisHash: string;
  sourceRef: string;
  sourceEstimateRef: string;
  cutoverAt: string;
  recordedAt: string;
  ledgerSeqBefore: number;
  ledgerSeqAfter: number;
  lineCount: number;
  positiveLineCount: number;
  totalQuantity: number;
  verificationStatusCode: OpeningBalanceVerificationStatus;
  lines: Array<{
    lineNo: number;
    openingBalanceLineId: string;
    productId: string;
    productSku: string;
    batchId: string;
    batchCode: string;
    bucketCode: string;
    quantity: number;
    ledgerEntryId: string | null;
    batchBucketQtyBefore: number | null;
    batchBucketQtyAfter: number | null;
    productBucketQtyBefore: number | null;
    productBucketQtyAfter: number | null;
    verificationStatusCode: OpeningBalanceVerificationStatus;
  }>;
};


export type OpeningBalanceReversalPreviewBlocker = {
  code: string;
  message: string;
  activeCutoverId?: string;
};

export type OpeningBalanceReversalPreviewLine = {
  openingBalanceLineId: string;
  originalEntryId: string;
  lineNo: number;
  sourceLineRef: string;
  productId: string;
  productSku: string;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  bucketCode: "SELLABLE" | "QUARANTINE" | "DAMAGED";
  originalQuantity: number;
  reversalDelta: number;
  currentBatchBucketQty: number;
  resultingBatchBucketQty: number;
  currentProductSellableQty: number;
  currentProductQuarantineQty: number;
  currentProductDamagedQty: number;
  currentProductReservedQty: number;
  resultingProductSellableQty: number;
  resultingProductQuarantineQty: number;
  resultingProductDamagedQty: number;
  batchBalanceVersion: number;
  productPositionVersion: number;
  originalLedgerSeq: number;
};

export type OpeningBalanceReversalPreview = {
  status: "PREVIEW_READY" | "BLOCKED";
  eligible: boolean;
  basisHash: string;
  schemaVersion: number;
  cutoverId: string;
  cutoverNo: string;
  originalTransactionId: string | null;
  originalTransactionNo: string | null;
  lineCount: number;
  totalAbsoluteQuantity: number;
  verificationApplicationCount: number;
  lines: OpeningBalanceReversalPreviewLine[];
  blockers: OpeningBalanceReversalPreviewBlocker[];
};

export type OpeningBalanceReversalResponse = {
  status: "REVERSED";
  cutoverId: string;
  cutoverNo: string;
  originalTransactionId: string;
  originalTransactionNo: string;
  reversalRecordId: string;
  reversalTransactionId: string;
  reversalTransactionNo: string;
  lineCount: number;
  totalAbsoluteQuantity: number;
  previewBasisHash: string;
  idempotencyKey: string;
  requestHash: string;
  ledgerSeqBefore: number;
  ledgerSeqAfter: number;
  recordedAt: string;
  actorUserId: string;
};

export type OpeningBalanceReversalAudit = {
  reversal_record_id: string;
  organization_id: string;
  opening_balance_cutover_id: string;
  cutover_no: string;
  original_transaction_id: string;
  original_transaction_no: string;
  reversal_transaction_id: string;
  reversal_transaction_no: string;
  idempotency_command_id: string;
  preview_basis_hash: string;
  ledger_seq_before: number;
  ledger_seq_after: number;
  line_count: number;
  total_absolute_quantity: number;
  reversed_at: string;
  reversed_by: string | null;
  process_name: string | null;
  note: string;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type OpeningBalanceData = {
  batches: BatchInventory[];
  cutovers: OpeningBalanceCutover[];
  selectedCutover: OpeningBalanceCutover | null;
  selectedReversal: OpeningBalanceReversalAudit | null;
  lines: OpeningBalanceCutoverLine[];
  ledger: StockLedgerEntry[];
  reversalLedger: StockLedgerEntry[];
};

export async function createOpeningBalanceCutover(input: {
  organizationId?: string;
  sourceRef: string;
  cutoverAt: string;
  sourceEstimateRef: string;
  note: string;
  metadata?: Record<string, unknown>;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<OpeningBalanceCreateResponse>(
    "create_opening_balance_cutover",
    {
      p_organization_id: organizationId,
      p_source_ref: input.sourceRef,
      p_cutover_at: input.cutoverAt,
      p_source_estimate_ref: input.sourceEstimateRef,
      p_note: input.note,
      p_metadata: input.metadata ?? {},
    },
  );
}

export async function saveOpeningBalanceDraft(input: {
  organizationId?: string;
  cutoverId: string;
  expectedRowVersion: number;
  cutoverAt: string;
  sourceEstimateRef: string;
  note: string;
  lines: OpeningBalanceDraftLineInput[];
  metadata?: Record<string, unknown>;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<OpeningBalanceSaveResponse>(
    "save_opening_balance_cutover_draft",
    {
      p_organization_id: organizationId,
      p_cutover_id: input.cutoverId,
      p_expected_row_version: input.expectedRowVersion,
      p_cutover_at: input.cutoverAt,
      p_source_estimate_ref: input.sourceEstimateRef,
      p_note: input.note,
      p_lines: input.lines,
      p_metadata: input.metadata ?? {},
    },
  );
}

export async function submitOpeningBalanceReview(input: {
  organizationId?: string;
  cutoverId: string;
  expectedRowVersion: number;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<OpeningBalanceReviewResponse>(
    "submit_opening_balance_cutover_review",
    {
      p_organization_id: organizationId,
      p_cutover_id: input.cutoverId,
      p_expected_row_version: input.expectedRowVersion,
    },
  );
}

export async function previewOpeningBalanceCutover(
  cutoverId: string,
  organizationId?: string,
) {
  const resolvedOrganizationId =
    await resolveOrganizationId(organizationId);

  return callRpc<OpeningBalancePreview>(
    "preview_opening_balance_cutover",
    {
      p_organization_id: resolvedOrganizationId,
      p_cutover_id: cutoverId,
    },
  );
}

export async function postOpeningBalanceCutover(input: {
  organizationId?: string;
  cutoverId: string;
  idempotencyKey: string;
  previewBasisHash: string;
  confirmation: boolean;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<OpeningBalancePostResponse>(
    "post_opening_balance_cutover",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_cutover_id: input.cutoverId,
      p_preview_basis_hash: input.previewBasisHash,
      p_confirmation: input.confirmation,
    },
  );
}


export async function previewOpeningBalanceReversal(
  cutoverId: string,
  organizationId?: string,
) {
  const resolvedOrganizationId =
    await resolveOrganizationId(organizationId);

  return callRpc<OpeningBalanceReversalPreview>(
    "preview_opening_balance_reversal",
    {
      p_organization_id: resolvedOrganizationId,
      p_cutover_id: cutoverId,
    },
  );
}

export async function reverseOpeningBalanceCutover(input: {
  organizationId?: string;
  cutoverId: string;
  idempotencyKey: string;
  previewBasisHash: string;
  confirmation: boolean;
  note: string;
  metadata?: Record<string, unknown>;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<OpeningBalanceReversalResponse>(
    "reverse_opening_balance_cutover",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_cutover_id: input.cutoverId,
      p_preview_basis_hash: input.previewBasisHash,
      p_confirmation: input.confirmation,
      p_note: input.note,
      p_metadata: input.metadata ?? {},
    },
  );
}

const OPENING_BALANCE_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function getOpeningBalanceData(
  organizationId?: string,
  selectedCutoverId?: string,
): Promise<OpeningBalanceData> {
  const resolvedOrganizationId =
    await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(
    resolvedOrganizationId,
  );
  const normalizedCutoverId = selectedCutoverId?.trim() ?? "";
  const selectedIsValid =
    OPENING_BALANCE_UUID_PATTERN.test(normalizedCutoverId);
  const encodedCutoverId = encodeURIComponent(normalizedCutoverId);

  const selectedPromise = selectedIsValid
    ? apiFetch<OpeningBalanceCutover[]>(
        `opening_balance_cutovers?organization_id=eq.${encodedOrganizationId}` +
          `&cutover_id=eq.${encodedCutoverId}&select=*&limit=1`,
      )
    : Promise.resolve([]);
  const selectedReversalPromise = selectedIsValid
    ? apiFetch<OpeningBalanceReversalAudit[]>(
        `opening_balance_cutover_reversals?organization_id=eq.${encodedOrganizationId}` +
          `&opening_balance_cutover_id=eq.${encodedCutoverId}&select=*&limit=1`,
      )
    : Promise.resolve([]);

  const [
    batches,
    recentCutovers,
    selectedRows,
    selectedReversalRows,
  ] = await Promise.all([
    apiFetchAll<BatchInventory>(
      `batch_inventory?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=product_name.asc,expiry_date.asc,batch_code.asc",
    ),
    apiFetch<OpeningBalanceCutover[]>(
      `opening_balance_cutovers?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=created_at.desc&limit=50",
    ),
    selectedPromise,
    selectedReversalPromise,
  ]);

  const selectedCutover = selectedRows[0] ?? null;
  const selectedReversal = selectedReversalRows[0] ?? null;
  const [lines, ledger, reversalLedger] = selectedCutover
    ? await Promise.all([
        apiFetchAll<OpeningBalanceCutoverLine>(
          `opening_balance_cutover_lines?organization_id=eq.${encodedOrganizationId}` +
            `&cutover_id=eq.${encodeURIComponent(selectedCutover.cutover_id)}` +
            "&select=*&order=line_no.asc",
        ),
        selectedCutover.transaction_id
          ? apiFetchAll<StockLedgerEntry>(
              `stock_ledger?organization_id=eq.${encodedOrganizationId}` +
                `&transaction_id=eq.${encodeURIComponent(selectedCutover.transaction_id)}` +
                "&select=*&order=line_no.asc,ledger_seq.asc",
            )
          : Promise.resolve([]),
        selectedReversal?.reversal_transaction_id
          ? apiFetchAll<StockLedgerEntry>(
              `stock_ledger?organization_id=eq.${encodedOrganizationId}` +
                `&transaction_id=eq.${encodeURIComponent(selectedReversal.reversal_transaction_id)}` +
                "&select=*&order=line_no.asc,ledger_seq.asc",
            )
          : Promise.resolve([]),
      ])
    : [[], [], []];

  const byId = new Map(
    [...recentCutovers, ...selectedRows].map((cutover) => [
      cutover.cutover_id,
      cutover,
    ]),
  );

  return {
    batches,
    cutovers: [...byId.values()].sort(
      (left, right) =>
        new Date(right.created_at).getTime() -
        new Date(left.created_at).getTime(),
    ),
    selectedCutover,
    selectedReversal,
    lines,
    ledger,
    reversalLedger,
  };
}
// OPENING_BALANCE_ADMIN_WORKFLOW_END
// MARKETPLACE_LISTING_SIMULATOR_START
export type MarketplaceListingCatalogRow = {
  listing_id: string;
  organization_id: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  external_listing_code: string;
  display_name: string;
  listing_type_code: "SINGLE" | "BUNDLE";
  status_code: "ACTIVE" | "ARCHIVED";
  current_version: number | null;
  effective_from: string | null;
  effective_to: string | null;
  product_id: string | null;
  bundle_recipe_id: string | null;
  mapping_fingerprint: string | null;
  created_at: string;
  updated_at: string;
  row_version: number;
  current_mapping_status_code: "DRAFT" | "ACTIVE" | "RETIRED" | null;
  mapping_readiness_code: "PUBLISHED" | "DRAFT_ONLY" | "MISSING" | "ARCHIVED";
  draft_version_count: number;
};

export type MarketplaceListingNormalization = {
  normalization_event_id: string;
  organization_id: string;
  marketplace_event_id: string;
  order_id: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  external_event_ref_snapshot: string;
  external_order_ref_snapshot: string;
  event_source_status: string;
  occurred_at: string;
  received_at: string;
  raw_payload_hash: string;
  normalization_schema_version: number;
  actor_user_id: string | null;
  process_name: string | null;
  metadata: Record<string, unknown>;
  source_line_id: string;
  source_line_no: number;
  source_line_ref: string;
  listing_id: string;
  external_listing_code_snapshot: string;
  listing_name_snapshot: string;
  listing_type_code_snapshot: "SINGLE" | "BUNDLE";
  listing_quantity: number;
  mapping_version: number;
  single_listing_version_id: string | null;
  bundle_recipe_id: string | null;
  mapping_fingerprint: string;
  source_title_snapshot: string | null;
  source_sku_snapshot: string | null;
  line_source_status: string | null;
  raw_line_hash: string;
  source_component_id: string;
  component_no: number;
  recipe_component_id: string | null;
  order_item_id: string;
  reserve_event_line_id: string;
  product_id: string;
  canonical_source_line_ref: string;
  product_sku_snapshot: string;
  product_name_snapshot: string;
  unit_quantity_per_listing: number;
  expanded_quantity: number;
  reservation_id: string;
  reserved_qty: number;
  consumed_qty: number;
  released_qty: number;
  reservation_status_code: string;
  created_at: string;
};

export type MarketplaceListingComponentLifecycle = {
  organization_id: string;
  order_id: string;
  external_order_ref: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  source_line_id: string;
  source_line_ref: string;
  listing_id: string;
  external_listing_code_snapshot: string;
  listing_name_snapshot: string;
  listing_type_code_snapshot: "SINGLE" | "BUNDLE";
  listing_quantity: number;
  mapping_version: number;
  mapping_fingerprint: string;
  source_component_id: string;
  component_no: number;
  recipe_component_id: string | null;
  order_item_id: string;
  product_id: string;
  product_sku_snapshot: string;
  product_name_snapshot: string;
  canonical_source_line_ref: string;
  unit_quantity_per_listing: number;
  expanded_quantity: number;
  reservation_id: string;
  reserved_qty: number;
  consumed_qty: number;
  released_qty: number;
  reservation_status_code: string;
  shipped_quantity: number;
  pre_shipment_cancelled_quantity: number;
  post_shipment_cancelled_quantity: number;
  return_expected_quantity: number;
  return_received_quantity: number;
  return_sellable_quantity: number;
  return_damaged_quantity: number;
  return_lost_quantity: number;
  open_reserved_quantity: number;
  remaining_returnable_or_cancellable_quantity: number;
};

export type MarketplaceListingSourceLineInput = {
  sourceLineRef: string;
  externalListingCode: string;
  listingQuantity: number;
  sourceTitle?: string | null;
  sourceSku?: string | null;
  sourceStatus?: string | null;
  rawLinePayload?: Record<string, unknown>;
};

export type MarketplaceListingComponentSelectionInput = {
  orderSourceLineRef: string;
  componentNo: number;
  quantity: number;
};

export type MarketplaceListingEventResponse = {
  status: "APPLIED";
  orderRef: string;
  eventType: string;
  totalQuantity: number;
  allocationCount: number;
  transactionNo: string | null;
  canonicalLineCount?: number;
  totalUnitQuantity?: number;
  normalizationEventId?: string;
  sourceLines?: unknown[];
  sourceComponents?: unknown[];
  adapterContract?: string;
};

export type MarketplaceListingSimulatorData = {
  listingCatalog: MarketplaceListingCatalogRow[];
  normalizations: MarketplaceListingNormalization[];
  components: MarketplaceListingComponentLifecycle[];
};

export async function reserveMarketplaceListingEvent(input: {
  organizationId?: string;
  idempotencyKey: string;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  eventRef: string;
  orderRef: string;
  sourceStatus: string;
  occurredAt: string;
  receivedAt: string;
  lines: MarketplaceListingSourceLineInput[];
  note?: string | null;
  rawPayload?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  schemaVersion?: number;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingEventResponse>(
    "reserve_marketplace_listing_event",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_channel_code: input.channelCode,
      p_event_ref: input.eventRef,
      p_order_ref: input.orderRef,
      p_source_status: input.sourceStatus,
      p_occurred_at: input.occurredAt,
      p_received_at: input.receivedAt,
      p_lines: input.lines,
      p_note: input.note ?? null,
      p_raw_payload: input.rawPayload ?? {},
      p_metadata: input.metadata ?? {},
      p_schema_version: input.schemaVersion ?? 1,
    },
  );
}

export async function shipMarketplaceListingEvent(input: {
  organizationId?: string;
  idempotencyKey: string;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  eventRef: string;
  orderRef: string;
  sourceStatus: string;
  occurredAt: string;
  receivedAt: string;
  lines: MarketplaceListingComponentSelectionInput[];
  note?: string | null;
  rawPayload?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  schemaVersion?: number;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingEventResponse>(
    "ship_marketplace_listing_event",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_channel_code: input.channelCode,
      p_event_ref: input.eventRef,
      p_order_ref: input.orderRef,
      p_source_status: input.sourceStatus,
      p_occurred_at: input.occurredAt,
      p_received_at: input.receivedAt,
      p_lines: input.lines,
      p_note: input.note ?? null,
      p_raw_payload: input.rawPayload ?? {},
      p_metadata: input.metadata ?? {},
      p_schema_version: input.schemaVersion ?? 1,
    },
  );
}

export async function getMarketplaceListingSimulatorData(
  organizationId?: string,
): Promise<MarketplaceListingSimulatorData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [listingCatalog, normalizations, components] = await Promise.all([
    apiFetch<MarketplaceListingCatalogRow[]>(
      `marketplace_listing_catalog?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=channel_code.asc,external_listing_code.asc&limit=300",
    ),
    apiFetch<MarketplaceListingNormalization[]>(
      `marketplace_listing_normalizations?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=occurred_at.desc,source_line_no.asc,component_no.asc&limit=300",
    ),
    apiFetch<MarketplaceListingComponentLifecycle[]>(
      `marketplace_listing_component_lifecycle?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=external_order_ref.desc,source_line_ref.asc,component_no.asc&limit=300",
    ),
  ]);

  return { listingCatalog, normalizations, components };
}
// MARKETPLACE_LISTING_SIMULATOR_END
// MARKETPLACE_LISTING_ADMIN_UI_START
export type MarketplaceListingVersionRow = {
  organization_id: string;
  listing_id: string;
  channel_code: "SHOPEE" | "TIKTOK_SHOP";
  external_listing_code: string;
  display_name: string;
  listing_type_code: "SINGLE" | "BUNDLE";
  version_id: string;
  version: number;
  status_code: "DRAFT" | "ACTIVE" | "RETIRED";
  effective_from: string;
  effective_to: string | null;
  product_id: string | null;
  bundle_recipe_id: string | null;
  mapping_fingerprint: string | null;
  component_count: number;
  row_version: number;
  note: string | null;
  metadata: Record<string, unknown>;
  activated_at: string | null;
  activated_by: string | null;
  retired_at: string | null;
  retired_by: string | null;
  created_at: string;
  created_by: string | null;
  updated_at: string;
  updated_by: string | null;
};

export type MarketplaceBundleRecipeComponentRow = {
  organization_id: string;
  listing_id: string;
  version_id: string;
  version: number;
  status_code: "DRAFT" | "ACTIVE" | "RETIRED";
  component_id: string;
  line_no: number;
  product_id: string;
  product_sku: string;
  product_name: string;
  product_is_active: boolean;
  component_qty: number;
};

export type MarketplaceListingAdminData = {
  listings: MarketplaceListingCatalogRow[];
  versions: MarketplaceListingVersionRow[];
  bundleComponents: MarketplaceBundleRecipeComponentRow[];
  products: ProductInventory[];
  normalizations: MarketplaceListingNormalization[];
};

export type MarketplaceListingDraftCreatedResponse = {
  status: "DRAFT_CREATED";
  listingId: string;
  versionId: string;
  version: number;
  versionRowVersion: number;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  externalListingCode: string;
  displayName: string;
  listingType: "SINGLE" | "BUNDLE";
  effectiveFrom: string;
  componentCount: number;
  createdAt: string;
};

export type MarketplaceListingDraftSavedResponse = {
  status: "DRAFT_SAVED";
  listingId: string;
  versionId: string;
  versionRowVersion: number;
  displayName: string;
  listingType: "SINGLE" | "BUNDLE";
  effectiveFrom: string;
  componentCount: number;
};

export type MarketplaceListingDraftMutationResponse =
  | MarketplaceListingDraftCreatedResponse
  | MarketplaceListingDraftSavedResponse;

export type MarketplaceListingActivationPreviewBlocker = {
  code: string;
  scope: string;
  message: string;
};

export type MarketplaceListingActivationPreviewComponent = {
  active: boolean;
  lineNo: number;
  quantity: number;
  productId: string;
  productSku: string;
  productName: string;
};

export type MarketplaceListingActivationPreview = {
  status: "PREVIEW_READY";
  eligible: boolean;
  blockers: MarketplaceListingActivationPreviewBlocker[];
  basisHash: string;
  listingId: string;
  versionId: string;
  version: number;
  listingType: "SINGLE" | "BUNDLE";
  effectiveFrom: string;
  componentCount: number;
  components: MarketplaceListingActivationPreviewComponent[];
  listingRowVersion: number;
  versionRowVersion: number;
  mappingFingerprint: string;
  currentOpenVersionId: string | null;
  currentOpenVersion: number | null;
  currentOpenRowVersion: number | null;
};

export type MarketplaceListingActivationResponse = {
  status: "ACTIVATED";
  listingId: string;
  versionId: string;
  version: number;
  listingType: "SINGLE" | "BUNDLE";
  effectiveFrom: string;
  activatedAt: string;
  closedVersionId: string | null;
  previewBasisHash: string;
  mappingFingerprint?: string;
};

export type MarketplaceListingRetirementResponse = {
  status: "RETIRED";
  listingId: string;
  versionId: string;
  version: number;
  effectiveTo: string;
  retiredAt: string;
};

export type MarketplaceListingArchiveResponse = {
  status: "ARCHIVED";
  listingId: string;
  externalListingCode: string;
  archivedAt: string;
  listingRowVersion: number;
};

export async function createMarketplaceListingVersionDraft(input: {
  organizationId?: string;
  idempotencyKey: string;
  channelCode: "SHOPEE" | "TIKTOK_SHOP";
  externalListingCode: string;
  displayName: string;
  listingTypeCode: "SINGLE" | "BUNDLE";
  effectiveFrom: string;
  productId?: string | null;
  components?: Array<{ productId: string; quantity: number }>;
  note?: string | null;
  metadata?: Record<string, unknown>;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingDraftCreatedResponse>(
    "create_marketplace_listing_version_draft",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_channel_code: input.channelCode,
      p_external_listing_code: input.externalListingCode,
      p_display_name: input.displayName,
      p_listing_type_code: input.listingTypeCode,
      p_effective_from: input.effectiveFrom,
      p_product_id: input.productId ?? null,
      p_components: input.components ?? [],
      p_note: input.note ?? null,
      p_metadata: input.metadata ?? {},
    },
  );
}

export async function saveMarketplaceListingVersionDraft(input: {
  organizationId?: string;
  listingId: string;
  versionId: string;
  expectedRowVersion: number;
  displayName: string;
  effectiveFrom: string;
  productId?: string | null;
  components?: Array<{ productId: string; quantity: number }>;
  note?: string | null;
  metadata?: Record<string, unknown>;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingDraftSavedResponse>(
    "save_marketplace_listing_version_draft",
    {
      p_organization_id: organizationId,
      p_listing_id: input.listingId,
      p_version_id: input.versionId,
      p_expected_row_version: input.expectedRowVersion,
      p_display_name: input.displayName,
      p_effective_from: input.effectiveFrom,
      p_product_id: input.productId ?? null,
      p_components: input.components ?? [],
      p_note: input.note ?? null,
      p_metadata: input.metadata ?? {},
    },
  );
}

export async function previewMarketplaceListingVersionActivation(input: {
  organizationId?: string;
  listingId: string;
  versionId: string;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingActivationPreview>(
    "preview_marketplace_listing_version_activation",
    {
      p_organization_id: organizationId,
      p_listing_id: input.listingId,
      p_version_id: input.versionId,
    },
  );
}

export async function activateMarketplaceListingVersion(input: {
  organizationId?: string;
  idempotencyKey: string;
  listingId: string;
  versionId: string;
  expectedRowVersion: number;
  previewBasisHash: string;
  confirmation: boolean;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingActivationResponse>(
    "activate_marketplace_listing_version",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_listing_id: input.listingId,
      p_version_id: input.versionId,
      p_expected_row_version: input.expectedRowVersion,
      p_preview_basis_hash: input.previewBasisHash,
      p_confirmation: input.confirmation,
    },
  );
}

export async function retireMarketplaceListingVersion(input: {
  organizationId?: string;
  idempotencyKey: string;
  listingId: string;
  versionId: string;
  expectedRowVersion: number;
  effectiveTo: string;
  confirmation: boolean;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingRetirementResponse>(
    "retire_marketplace_listing_version",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_listing_id: input.listingId,
      p_version_id: input.versionId,
      p_expected_row_version: input.expectedRowVersion,
      p_effective_to: input.effectiveTo,
      p_confirmation: input.confirmation,
    },
  );
}

export async function archiveMarketplaceListing(input: {
  organizationId?: string;
  idempotencyKey: string;
  listingId: string;
  expectedRowVersion: number;
  confirmation: boolean;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);

  return callRpc<MarketplaceListingArchiveResponse>(
    "archive_marketplace_listing",
    {
      p_organization_id: organizationId,
      p_idempotency_key: input.idempotencyKey,
      p_listing_id: input.listingId,
      p_expected_row_version: input.expectedRowVersion,
      p_confirmation: input.confirmation,
    },
  );
}

export async function getMarketplaceListingAdminData(
  organizationId?: string,
): Promise<MarketplaceListingAdminData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);

  const [
    listings,
    versions,
    bundleComponents,
    products,
    normalizations,
  ] = await Promise.all([
    apiFetch<MarketplaceListingCatalogRow[]>(
      `marketplace_listing_catalog?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=channel_code.asc,external_listing_code.asc&limit=500",
    ),
    apiFetch<MarketplaceListingVersionRow[]>(
      `marketplace_listing_versions?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=external_listing_code.asc,version.desc&limit=1000",
    ),
    apiFetch<MarketplaceBundleRecipeComponentRow[]>(
      `marketplace_bundle_recipe_components?organization_id=eq.${encodedOrganizationId}` +
        "&select=*&order=version_id.asc,line_no.asc&limit=2000",
    ),
    apiFetch<ProductInventory[]>(
      `product_inventory?organization_id=eq.${encodedOrganizationId}` +
        "&is_active=eq.true&select=*&order=sku.asc&limit=500",
    ),
    apiFetch<MarketplaceListingNormalization[]>(
      `marketplace_listing_normalizations?organization_id=eq.${encodedOrganizationId}` +
        "&select=listing_id,mapping_version,order_id&order=occurred_at.desc&limit=2000",
    ),
  ]);

  return {
    listings,
    versions,
    bundleComponents,
    products,
    normalizations,
  };
}
// MARKETPLACE_LISTING_ADMIN_UI_END

export type ProductMasterRow = {
  product_id: string;
  organization_id: string;
  sku: string;
  name: string;
  unit_code: "UNIT";
  description: string | null;
  is_active: boolean;
  row_version: number;
  created_at: string;
  created_by: string | null;
  updated_at: string;
  updated_by: string | null;
  sellable_qty: number;
  quarantine_qty: number;
  damaged_qty: number;
  reserved_qty: number;
  available_qty: number;
  last_ledger_seq: number;
  has_authoritative_history: boolean;
  batch_count: number;
  listing_reference_count: number;
};

export type ProductMasterAuditRow = {
  audit_id: string;
  organization_id: string;
  product_id: string;
  action_code: "PRODUCT_CREATE" | "PRODUCT_UPDATE" | "PRODUCT_ARCHIVE" | "PRODUCT_REACTIVATE";
  idempotency_command_id: string;
  command_scope: string;
  idempotency_key: string;
  before_snapshot: Record<string, unknown> | null;
  after_snapshot: Record<string, unknown> | null;
  reason: string | null;
  note: string | null;
  actor_user_id: string | null;
  actor_display_name: string | null;
  process_name: string | null;
  occurred_at: string;
  recorded_at: string;
  schema_version: number;
};

export type ProductCommandResponse = {
  status: "CREATED" | "UPDATED" | "ARCHIVED" | "REACTIVATED";
  productId: string;
  sku: string;
  name?: string;
  unitCode?: "UNIT";
  description?: string | null;
  isActive: boolean;
  rowVersion: number;
  auditId: string;
  idempotencyKey: string;
  stockEffect: "NONE";
  recordedAt: string;
};

export type ProductMasterData = {
  products: ProductMasterRow[];
  audits: ProductMasterAuditRow[];
};

export async function createProduct(input: {
  organizationId?: string;
  idempotencyKey: string;
  sku: string;
  name: string;
  unitCode?: "UNIT";
  description?: string | null;
  note?: string | null;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);
  return callRpc<ProductCommandResponse>("create_product", {
    p_organization_id: organizationId,
    p_idempotency_key: input.idempotencyKey,
    p_sku: input.sku,
    p_name: input.name,
    p_unit_code: input.unitCode ?? "UNIT",
    p_description: input.description ?? null,
    p_note: input.note ?? null,
  });
}

export async function updateProduct(input: {
  organizationId?: string;
  idempotencyKey: string;
  productId: string;
  expectedRowVersion: number;
  sku: string;
  name: string;
  unitCode?: "UNIT";
  description?: string | null;
  note?: string | null;
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);
  return callRpc<ProductCommandResponse>("update_product", {
    p_organization_id: organizationId,
    p_idempotency_key: input.idempotencyKey,
    p_product_id: input.productId,
    p_expected_row_version: input.expectedRowVersion,
    p_sku: input.sku,
    p_name: input.name,
    p_unit_code: input.unitCode ?? "UNIT",
    p_description: input.description ?? null,
    p_note: input.note ?? null,
  });
}

async function changeProductState(input: {
  organizationId?: string;
  idempotencyKey: string;
  productId: string;
  expectedRowVersion: number;
  reason?: string | null;
  command: "archive_product" | "reactivate_product";
}) {
  const organizationId = await resolveOrganizationId(input.organizationId);
  return callRpc<ProductCommandResponse>(input.command, {
    p_organization_id: organizationId,
    p_idempotency_key: input.idempotencyKey,
    p_product_id: input.productId,
    p_expected_row_version: input.expectedRowVersion,
    p_reason: input.reason ?? null,
  });
}

export async function archiveProduct(input: Omit<Parameters<typeof changeProductState>[0], "command">) {
  return changeProductState({ ...input, command: "archive_product" });
}

export async function reactivateProduct(input: Omit<Parameters<typeof changeProductState>[0], "command">) {
  return changeProductState({ ...input, command: "reactivate_product" });
}

export async function getProductMasterData(organizationId?: string): Promise<ProductMasterData> {
  const resolvedOrganizationId = await resolveOrganizationId(organizationId);
  const encodedOrganizationId = encodeURIComponent(resolvedOrganizationId);
  const [products, audits] = await Promise.all([
    apiFetch<ProductMasterRow[]>(
      `product_master?organization_id=eq.${encodedOrganizationId}&select=*&order=is_active.desc,name.asc&limit=1000`,
    ),
    apiFetch<ProductMasterAuditRow[]>(
      `product_master_audit?organization_id=eq.${encodedOrganizationId}&select=*&order=occurred_at.desc&limit=2000`,
    ),
  ]);
  return { products, audits };
}