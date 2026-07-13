import "server-only";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";
const DEFAULT_ORGANIZATION_ID = "00000000-0000-4000-8000-000000000001";

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

export type DashboardData = {
  products: ProductInventory[];
  batches: BatchInventory[];
  ledger: StockLedgerEntry[];
};

function getConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL;
  const secretKey = process.env.SUPABASE_SECRET_KEY;
  const organizationId =
    process.env.DEMO_ORGANIZATION_ID ?? DEFAULT_ORGANIZATION_ID;

  if (!secretKey || secretKey.includes("REPLACE_ME")) {
    throw new Error(
      "SUPABASE_SECRET_KEY belum dikonfigurasi. Salin key lokal dari `npx supabase status -o env` ke `.env.local`.",
    );
  }

  return { url: url.replace(/\/$/, ""), secretKey, organizationId };
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
  const { url, secretKey } = getConfig();
  const headers = new Headers(init.headers);

  headers.set("apikey", secretKey);
  headers.set("Authorization", `Bearer ${secretKey}`);
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

export function getOrganizationId() {
  return getConfig().organizationId;
}

export async function getDashboardData(): Promise<DashboardData> {
  const organizationId = getOrganizationId();
  const encodedOrganizationId = encodeURIComponent(organizationId);

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

export async function callRpc<T>(name: string, body: Record<string, unknown>) {
  return apiFetch<T>(`rpc/${name}`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}
