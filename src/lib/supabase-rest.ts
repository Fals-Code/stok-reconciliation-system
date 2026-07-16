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
  batch_id: string;
  quantity_received: number;
  batch_identity_verified: boolean;
  product_sku_snapshot: string;
  batch_code_snapshot: string;
  expiry_date_snapshot: string;
  source_line_ref: string;
  ledger_entry_id: string;
  occurred_at: string;
  created_at: string;
};

export type ReturnInspectionAllocation = {
  inspection_allocation_id: string;
  organization_id: string;
  return_id: string;
  inspection_id: string;
  inspection_ref: string;
  receipt_line_id: string;
  allocation_no: number;
  destination_bucket_code: "SELLABLE" | "DAMAGED";
  quantity_allocated: number;
  pair_no: number;
  source_ledger_entry_id: string;
  destination_ledger_entry_id: string;
  occurred_at: string;
  created_at: string;
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
