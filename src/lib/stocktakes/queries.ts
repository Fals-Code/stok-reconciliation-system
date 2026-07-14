import "server-only";

import { getAdminSession } from "@/lib/auth";
import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakeBatchOption,
  StocktakeCountAttempt,
  StocktakeCreateOptions,
  StocktakeCountingLine,
  StocktakeDetailData,
  StocktakeDetails,
  StocktakeListItem,
  StocktakeProductOption,
  StocktakeReviewLine,
  StocktakeVisibility,
} from "@/lib/stocktakes/types";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";

function getConfig() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(
    /\/$/,
    "",
  );
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!publishableKey || publishableKey.includes("REPLACE_ME")) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum dikonfigurasi di .env.local.",
    );
  }

  return { url, publishableKey };
}

async function responseError(response: Response) {
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

async function getRequestContext() {
  const session = await getAdminSession();

  if (!session) {
    throw new Error("AUTH_SESSION_REQUIRED");
  }

  const config = getConfig();
  return { session, ...config };
}

async function authenticatedFetch<T>(
  path: string,
  context: Awaited<ReturnType<typeof getRequestContext>>,
): Promise<T> {
  const response = await fetch(`${context.url}/rest/v1/${path}`, {
    headers: {
      apikey: context.publishableKey,
      Authorization: `Bearer ${context.session.accessToken}`,
      "Accept-Profile": "api",
    },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(await responseError(response));
  }

  return (await response.json()) as T;
}

export async function getStocktakeList(): Promise<StocktakeListItem[]> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );

  return authenticatedFetch<StocktakeListItem[]>(
    `stocktake_list?organization_id=eq.${organizationId}&select=*&order=updated_at.desc,created_at.desc`,
    context,
  );
}

export async function getStocktakeCreateOptions(): Promise<StocktakeCreateOptions> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );

  const [products, batches] = await Promise.all([
    authenticatedFetch<StocktakeProductOption[]>(
      `product_inventory?organization_id=eq.${organizationId}&select=product_id,organization_id,sku,name,is_active,sellable_qty,quarantine_qty,damaged_qty&order=name.asc`,
      context,
    ),
    authenticatedFetch<StocktakeBatchOption[]>(
      `batch_inventory?organization_id=eq.${organizationId}&select=batch_id,organization_id,product_id,sku,product_name,batch_code,expiry_date,status_code,sellable_qty,quarantine_qty,damaged_qty&order=product_name.asc,expiry_date.asc,batch_code.asc`,
      context,
    ),
  ]);

  return { products, batches };
}

export async function getStocktakeDetails(
  stocktakeId: string,
): Promise<StocktakeDetailData | null> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);

  const [detailsRows, summaryRows] = await Promise.all([
    authenticatedFetch<StocktakeDetails[]>(
      `stocktake_details?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&limit=1`,
      context,
    ),
    authenticatedFetch<StocktakeListItem[]>(
      `stocktake_list?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&limit=1`,
      context,
    ),
  ]);

  const details = detailsRows[0];
  if (!details) {
    return null;
  }

  return {
    details,
    summary: summaryRows[0] ?? null,
  };
}

export async function getStocktakeCountingLines(
  stocktakeId: string,
  visibility: StocktakeVisibility,
): Promise<StocktakeCountingLine[]> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);
  const view =
    visibility === "BLIND"
      ? "stocktake_blind_lines"
      : "stocktake_non_blind_lines";

  return authenticatedFetch<StocktakeCountingLine[]>(
    `${view}?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&order=line_no.asc`,
    context,
  );
}


export async function getStocktakeReviewLines(
  stocktakeId: string,
): Promise<StocktakeReviewLine[]> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);

  return authenticatedFetch<StocktakeReviewLine[]>(
    `stocktake_review_lines?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&order=line_no.asc`,
    context,
  );
}

export async function getStocktakeCountAttempts(
  stocktakeId: string,
): Promise<StocktakeCountAttempt[]> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);

  return authenticatedFetch<StocktakeCountAttempt[]>(
    `stocktake_count_attempts?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&order=stocktake_line_id.asc,attempt_no.asc`,
    context,
  );
}


export async function getLatestStocktakeApproval(
  stocktakeId: string,
): Promise<StocktakeApproval | null> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);

  const rows = await authenticatedFetch<StocktakeApproval[]>(
    `stocktake_approvals?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&select=*&order=approval_version_no.desc&limit=1`,
    context,
  );

  return rows[0] ?? null;
}

export async function getStocktakeApprovalLines(
  stocktakeId: string,
  approvalId: string,
): Promise<StocktakeApprovalLine[]> {
  const context = await getRequestContext();
  const organizationId = encodeURIComponent(
    context.session.profile.organization_id,
  );
  const encodedStocktakeId = encodeURIComponent(stocktakeId);
  const encodedApprovalId = encodeURIComponent(approvalId);

  return authenticatedFetch<StocktakeApprovalLine[]>(
    `stocktake_approval_lines?organization_id=eq.${organizationId}&stocktake_id=eq.${encodedStocktakeId}&approval_id=eq.${encodedApprovalId}&select=*&order=line_no.asc`,
    context,
  );
}
