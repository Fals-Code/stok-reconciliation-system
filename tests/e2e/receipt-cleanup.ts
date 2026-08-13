import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

export type ReceiptCleanupRequest = {
  sourceRef: string;
  archiveInlineBatch: boolean;
};

function readLocalEnvironment() {
  const values: Record<string, string> = {};

  try {
    const raw = readFileSync(".env.local", "utf8");

    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();

      if (!trimmed || trimmed.startsWith("#")) {
        continue;
      }

      const separator = line.indexOf("=");

      if (separator <= 0) {
        continue;
      }

      values[line.slice(0, separator).trim()] = line
        .slice(separator + 1)
        .trim()
        .replace(/^[`'"]|[`'"]$/g, "");
    }
  } catch {
    // Environment variables may be supplied directly by the test harness.
  }

  return values;
}

const localEnvironment = readLocalEnvironment();

const supabaseUrl = (
  process.env.NEXT_PUBLIC_SUPABASE_URL ??
  localEnvironment.NEXT_PUBLIC_SUPABASE_URL ??
  "http://127.0.0.1:54321"
).replace(/\/+$/, "");

const publishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  localEnvironment.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  "";

const adminEmail =
  process.env.PLAYWRIGHT_ADMIN_EMAIL ??
  "demo.admin@glowlab.invalid";

function getAdminPassword() {
  const password = process.env.PLAYWRIGHT_ADMIN_PASSWORD;

  if (!password) {
    throw new Error(
      "PLAYWRIGHT_ADMIN_PASSWORD belum tersedia untuk cleanup Receipt.",
    );
  }

  return password;
}

export async function cleanupReceiptMutation(
  request: ReceiptCleanupRequest,
) {
  if (!publishableKey) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum tersedia untuk cleanup Receipt.",
    );
  }

  const authResponse = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: adminEmail,
        password: getAdminPassword(),
      }),
    },
  );

  const authPayload = (await authResponse.json()) as {
    access_token?: string;
  };

  if (!authResponse.ok || !authPayload.access_token) {
    throw new Error(
      "Cleanup Receipt tidak dapat login sebagai Admin test.",
    );
  }

  const headers = {
    apikey: publishableKey,
    Authorization: `Bearer ${authPayload.access_token}`,
    "Content-Type": "application/json",
    "Accept-Profile": "api",
    "Content-Profile": "api",
  };

  async function rpc<T>(
    name: string,
    body: Record<string, unknown>,
  ) {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/rpc/${name}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      },
    );
    const raw = await response.text();

    if (!response.ok) {
      throw new Error(`Cleanup RPC ${name} gagal: ${raw}`);
    }

    return (raw ? JSON.parse(raw) : null) as T;
  }

  async function view<T>(pathname: string) {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/${pathname}`,
      { headers },
    );
    const raw = await response.text();

    if (!response.ok) {
      throw new Error(`Cleanup read ${pathname} gagal: ${raw}`);
    }

    return (raw ? JSON.parse(raw) : []) as T;
  }

  const profiles = await view<Array<{
    organization_id: string;
  }>>(
    "current_admin_profile?select=organization_id",
  );
  const organizationId = profiles[0]?.organization_id;

  if (!organizationId) {
    throw new Error(
      "Organisasi Admin test tidak tersedia untuk cleanup Receipt.",
    );
  }

  const organization = encodeURIComponent(organizationId);
  const sourceRef = encodeURIComponent(request.sourceRef);
  const receipts = await view<Array<{
    receipt_id: string;
    transaction_id: string;
  }>>(
    `receipts?organization_id=eq.${organization}&source_ref=eq.${sourceRef}&select=receipt_id,transaction_id&order=recorded_at.desc&limit=1`,
  );
  const receipt = receipts[0];

  if (!receipt) {
    return;
  }

  let inlineBatchId: string | null = null;

  if (request.archiveInlineBatch) {
    const lines = await view<Array<{ batch_id: string }>>(
      `receipt_lines?organization_id=eq.${organization}&receipt_id=eq.${encodeURIComponent(receipt.receipt_id)}&select=batch_id&order=line_no.asc&limit=1`,
    );
    inlineBatchId = lines[0]?.batch_id ?? null;

    if (!inlineBatchId) {
      throw new Error(
        "Batch inline Receipt tidak ditemukan untuk cleanup.",
      );
    }
  }

  const preview = await rpc<{
    eligible: boolean;
    basisHash: string;
    blockers?: Array<{ code?: string }>;
  }>(
    "preview_stock_transaction_reversal",
    {
      p_organization_id: organizationId,
      p_original_transaction_id: receipt.transaction_id,
    },
  );

  if (preview.eligible) {
    const reversal = await rpc<{ status?: string }>(
      "reverse_stock_transaction",
      {
        p_organization_id: organizationId,
        p_idempotency_key: `receipt-browser-cleanup:${randomUUID()}`,
        p_original_transaction_id: receipt.transaction_id,
        p_preview_basis_hash: preview.basisHash,
        p_confirmation: true,
        p_note: "Cleanup automated Receipt browser fixture.",
        p_metadata: {
          source: "receipt-browser-cleanup",
          version: 1,
          fixtureSourceRef: request.sourceRef,
        },
      },
    );

    if (reversal.status !== "REVERSED") {
      throw new Error(
        "Cleanup Receipt tidak menghasilkan status REVERSED.",
      );
    }
  } else {
    const alreadyReversed = (preview.blockers ?? []).some(
      (blocker) =>
        /ALREADY|REVERSED/i.test(String(blocker.code ?? "")),
    );

    if (!alreadyReversed) {
      throw new Error(
        `Cleanup Receipt tidak eligible: ${JSON.stringify(preview.blockers ?? [])}`,
      );
    }
  }

  if (!inlineBatchId) {
    return;
  }

  const batches = await view<Array<{
    row_version: number;
    lifecycle_status_code: string;
    sellable_qty: number;
    quarantine_qty: number;
    damaged_qty: number;
  }>>(
    `product_batch_master?organization_id=eq.${organization}&batch_id=eq.${encodeURIComponent(inlineBatchId)}&select=row_version,lifecycle_status_code,sellable_qty,quarantine_qty,damaged_qty&limit=1`,
  );
  const batch = batches[0];

  if (!batch) {
    throw new Error(
      "Batch inline Receipt tidak ditemukan setelah reversal.",
    );
  }

  const physicalQuantity =
    Number(batch.sellable_qty) +
    Number(batch.quarantine_qty) +
    Number(batch.damaged_qty);

  if (physicalQuantity !== 0) {
    throw new Error(
      `Cleanup Receipt tidak net-zero pada batch inline: ${physicalQuantity}.`,
    );
  }

  if (batch.lifecycle_status_code === "ARCHIVED") {
    return;
  }

  const archived = await rpc<{
    lifecycleStatusCode?: string;
  }>(
    "archive_product_batch",
    {
      p_organization_id: organizationId,
      p_idempotency_key: `receipt-browser-cleanup:archive:${randomUUID()}`,
      p_batch_id: inlineBatchId,
      p_expected_row_version: batch.row_version,
      p_reason: "Cleanup automated Receipt browser fixture",
      p_note: "Batch retained for audit after exact reversal.",
    },
  );

  if (archived.lifecycleStatusCode !== "ARCHIVED") {
    throw new Error(
      "Batch inline Receipt gagal diarsipkan setelah cleanup.",
    );
  }
}