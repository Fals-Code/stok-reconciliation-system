"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import { callRpc } from "@/lib/supabase-rest";
import { stocktakeErrorMessage } from "@/lib/stocktakes/errors";
import { stocktakePostingIdempotencyKey } from "@/lib/stocktakes/posting";
import {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
  type StocktakeApprovalResponse,
  type StocktakeBucket,
  type StocktakeCompleteCountingResponse,
  type StocktakeCountResponse,
  type StocktakeCreateResponse,
  type StocktakePostingResponse,
  type StocktakePrepareResponse,
  type StocktakeRecountResponse,
  type StocktakeReviewRecountResponse,
  type StocktakeReviewResponse,
  type StocktakeScopeDefinition,
  type StocktakeScopeMode,
  type StocktakeStartResponse,
  type StocktakeType,
  type StocktakeVisibility,
} from "@/lib/stocktakes/types";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function requiredUuid(
  formData: FormData,
  key: string,
  errorCode = "STOCKTAKE_ID_REQUIRED",
) {
  const value = required(formData, key);

  if (!UUID_PATTERN.test(value)) {
    throw new Error(errorCode);
  }

  return value;
}

function enumValue<T extends string>(
  formData: FormData,
  key: string,
  allowed: readonly T[],
  errorCode: string,
): T {
  const value = required(formData, key).toUpperCase();

  if (!allowed.includes(value as T)) {
    throw new Error(errorCode);
  }

  return value as T;
}

function uniqueValues(formData: FormData, key: string) {
  const values = formData
    .getAll(key)
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim())
    .filter(Boolean);

  return Array.from(new Set(values));
}

function checkbox(formData: FormData, key: string) {
  return formData.get(key) === "on";
}

function requiredNonnegativeInteger(formData: FormData, key: string) {
  const raw = required(formData, key);

  if (!/^\d+$/.test(raw)) {
    throw new Error("STOCKTAKE_INVALID_PHYSICAL_QTY");
  }

  const value = Number(raw);

  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("STOCKTAKE_INVALID_PHYSICAL_QTY");
  }

  return value;
}

function requiredAttemptNo(formData: FormData) {
  const raw = required(formData, "attemptNo");

  if (!/^\d+$/.test(raw)) {
    throw new Error("STOCKTAKE_ATTEMPT_NO_INVALID");
  }

  const value = Number(raw);

  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("STOCKTAKE_ATTEMPT_NO_INVALID");
  }

  return value;
}

function requiredPositiveVersion(formData: FormData) {
  const raw = required(formData, "stocktakeVersion");

  if (!/^\d+$/.test(raw)) {
    throw new Error("STOCKTAKE_VERSION_INVALID");
  }

  const value = Number(raw);

  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error("STOCKTAKE_VERSION_INVALID");
  }

  return value;
}

function jakartaTimestampOrNull(raw: FormDataEntryValue | null) {
  if (raw === null || raw === "") {
    return null;
  }

  if (
    typeof raw !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(raw)
  ) {
    throw new Error("STOCKTAKE_PLANNED_AT_INVALID");
  }

  return `${raw}:00+07:00`;
}

function createScope(formData: FormData): StocktakeScopeDefinition {
  const mode = enumValue<StocktakeScopeMode>(
    formData,
    "scopeMode",
    STOCKTAKE_SCOPE_MODES,
    "STOCKTAKE_SCOPE_NOT_SUPPORTED",
  );

  const bucketCodes = uniqueValues(formData, "bucketCodes")
    .map((value) => value.toUpperCase())
    .filter((value): value is StocktakeBucket =>
      STOCKTAKE_BUCKETS.includes(value as StocktakeBucket),
    );

  if (bucketCodes.length === 0) {
    throw new Error("STOCKTAKE_SCOPE_REQUIRED");
  }

  const scope: StocktakeScopeDefinition = {
    mode,
    bucketCodes,
    includeZeroSystemBalance: checkbox(
      formData,
      "includeZeroSystemBalance",
    ),
    includeInactiveWithBalance: checkbox(
      formData,
      "includeInactiveWithBalance",
    ),
    includeBlockedBatches: checkbox(formData, "includeBlockedBatches"),
    includeExpiredBatches: checkbox(formData, "includeExpiredBatches"),
  };

  if (mode === "PRODUCTS") {
    const productIds = uniqueValues(formData, "productIds");
    if (productIds.length === 0) {
      throw new Error("STOCKTAKE_SCOPE_REQUIRED");
    }
    scope.productIds = productIds;
  }

  if (mode === "BATCHES") {
    const batchIds = uniqueValues(formData, "batchIds");
    if (batchIds.length === 0) {
      throw new Error("STOCKTAKE_SCOPE_REQUIRED");
    }
    scope.batchIds = batchIds;
  }

  return scope;
}

function detailDestination(
  stocktakeId: string,
  kind: "success" | "error",
  message: string,
) {
  const params = new URLSearchParams({ [kind]: message });
  return `/stocktakes/${encodeURIComponent(stocktakeId)}?${params.toString()}`;
}

function lifecycleMetadata(
  actorUserId: string,
  action:
    | "prepare"
    | "start"
    | "count"
    | "recount"
    | "complete-counting"
    | "review-line"
    | "review-recount"
    | "approve"
    | "post",
) {
  return {
    source: "admin-stocktake-ui",
    version: 1,
    action,
    actorUserId,
  };
}

export async function createStocktakeAction(formData: FormData) {
  const session = await requireAdminSession();
  const idempotencyKey = required(formData, "idempotencyKey");

  let destination: string;

  try {
    const title = required(formData, "title");
    const stocktakeTypeCode = enumValue<StocktakeType>(
      formData,
      "stocktakeTypeCode",
      STOCKTAKE_TYPES,
      "STOCKTAKE_TYPE_NOT_SUPPORTED",
    );
    const visibilityCode = enumValue<StocktakeVisibility>(
      formData,
      "visibilityCode",
      STOCKTAKE_VISIBILITIES,
      "STOCKTAKE_VISIBILITY_NOT_SUPPORTED",
    );
    const scope = createScope(formData);
    const plannedAt = jakartaTimestampOrNull(formData.get("plannedAt"));
    const note = String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<StocktakeCreateResponse>("create_stocktake", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: idempotencyKey,
      p_title: title,
      p_stocktake_type_code: stocktakeTypeCode,
      p_mode_code: "CONTINUOUS",
      p_visibility_code: visibilityCode,
      p_scope: scope,
      p_planned_at: plannedAt,
      p_note: note,
      p_metadata: {
        source: "admin-stocktake-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${result.stocktakeId}`);

    destination = detailDestination(
      result.stocktakeId,
      "success",
      `${result.stocktakeNo} berhasil dibuat sebagai Draft.`,
    );
  } catch (error) {
    const errorParams = new URLSearchParams({
      idempotencyKey,
      error: stocktakeErrorMessage(error),
    });

    destination = `/stocktakes/new?${errorParams.toString()}`;
  }

  redirect(destination);
}

export async function prepareStocktakeAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");

  let destination: string;

  try {
    const result = await callRpc<StocktakePrepareResponse>(
      "prepare_stocktake",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key: `stocktake:${stocktakeId}:prepare:v1`,
        p_stocktake_id: stocktakeId,
        p_metadata: lifecycleMetadata(session.user.id, "prepare"),
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `${result.stocktakeNo} siap dimulai. ${result.scopeLineCount} line scope tervalidasi pada ledger sequence ${result.validationLedgerSeq}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function startStocktakeAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");

  let destination: string;

  try {
    if (!checkbox(formData, "confirmStart")) {
      throw new Error("STOCKTAKE_START_CONFIRMATION_REQUIRED");
    }

    const result = await callRpc<StocktakeStartResponse>("start_stocktake", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: `stocktake:${stocktakeId}:start:v1`,
      p_stocktake_id: stocktakeId,
      p_metadata: lifecycleMetadata(session.user.id, "start"),
    });

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `${result.stocktakeNo} mulai dihitung. ${result.lineCount} line dibuat dari ledger sequence ${result.snapshotLedgerSeq}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function submitStocktakeCountAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeLineId = requiredUuid(
    formData,
    "stocktakeLineId",
    "STOCKTAKE_LINE_ID_REQUIRED",
  );
  const attemptNo = requiredAttemptNo(formData);

  let destination: string;

  try {
    const physicalQty = requiredNonnegativeInteger(formData, "physicalQty");
    const zeroConfirmed = checkbox(formData, "zeroConfirmed");
    const note = String(formData.get("note") ?? "").trim() || null;
    const nextAttemptNo = attemptNo + 1;

    const result = await callRpc<StocktakeCountResponse>(
      "submit_stocktake_count",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:line:${stocktakeLineId}:count:${nextAttemptNo}`,
        p_stocktake_id: stocktakeId,
        p_stocktake_line_id: stocktakeLineId,
        p_physical_qty: physicalQty,
        p_zero_confirmed: zeroConfirmed,
        p_count_method_code: "MANUAL_ENTRY",
        p_note: note,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "count"),
          attemptNo: nextAttemptNo,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Line berhasil disimpan sebagai attempt ${result.attemptNo}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function requestStocktakeRecountAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeLineId = requiredUuid(
    formData,
    "stocktakeLineId",
    "STOCKTAKE_LINE_ID_REQUIRED",
  );
  const attemptNo = requiredAttemptNo(formData);

  let destination: string;

  try {
    const reason = required(formData, "reason");

    const result = await callRpc<StocktakeRecountResponse>(
      "request_stocktake_recount",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:line:${stocktakeLineId}:recount:${attemptNo}`,
        p_stocktake_id: stocktakeId,
        p_stocktake_line_id: stocktakeLineId,
        p_reason: reason,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "recount"),
          attemptNo,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Line ditandai untuk hitung ulang setelah attempt ${result.currentAttemptNo}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function completeStocktakeCountingAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeVersion = requiredPositiveVersion(formData);

  let destination: string;

  try {
    const result = await callRpc<StocktakeCompleteCountingResponse>(
      "complete_stocktake_counting",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:complete-counting:${stocktakeVersion}`,
        p_stocktake_id: stocktakeId,
        p_metadata: {
          ...lifecycleMetadata(
            session.user.id,
            "complete-counting",
          ),
          stocktakeVersion,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `${result.stocktakeNo} masuk ke Review dengan ${result.varianceLineCount} line variance.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}


export async function reviewStocktakeLineAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeLineId = requiredUuid(
    formData,
    "stocktakeLineId",
    "STOCKTAKE_LINE_ID_REQUIRED",
  );
  const lineVersionRaw = required(formData, "lineVersion");

  if (!/^\d+$/.test(lineVersionRaw)) {
    throw new Error("STOCKTAKE_LINE_VERSION_REQUIRED");
  }

  const lineVersion = Number(lineVersionRaw);

  if (!Number.isSafeInteger(lineVersion) || lineVersion <= 0) {
    throw new Error("STOCKTAKE_LINE_VERSION_REQUIRED");
  }

  let destination: string;

  try {
    const decisionCode = required(formData, "decisionCode");
    const reasonCode =
      String(formData.get("reasonCode") ?? "").trim() || null;
    const reviewNote =
      String(formData.get("reviewNote") ?? "").trim() || null;
    const exceptionCode =
      String(formData.get("exceptionCode") ?? "").trim() || null;

    const result = await callRpc<StocktakeReviewResponse>(
      "review_stocktake_line",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:line:${stocktakeLineId}:review:${lineVersion}`,
        p_stocktake_id: stocktakeId,
        p_stocktake_line_id: stocktakeLineId,
        p_expected_line_version: lineVersion,
        p_decision_code: decisionCode,
        p_reason_code: reasonCode,
        p_review_note: reviewNote,
        p_exception_code: exceptionCode,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "review-line"),
          lineVersion,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Line ${result.stocktakeLineId.slice(0, 8)} direview sebagai ${result.decisionCode}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function requestStocktakeReviewRecountAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeLineId = requiredUuid(
    formData,
    "stocktakeLineId",
    "STOCKTAKE_LINE_ID_REQUIRED",
  );
  const lineVersionRaw = required(formData, "lineVersion");

  if (!/^\d+$/.test(lineVersionRaw)) {
    throw new Error("STOCKTAKE_LINE_VERSION_REQUIRED");
  }

  const lineVersion = Number(lineVersionRaw);

  if (!Number.isSafeInteger(lineVersion) || lineVersion <= 0) {
    throw new Error("STOCKTAKE_LINE_VERSION_REQUIRED");
  }

  let destination: string;

  try {
    const reason = required(formData, "reason");

    const result = await callRpc<StocktakeReviewRecountResponse>(
      "request_stocktake_review_recount",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:line:${stocktakeLineId}:review-recount:${lineVersion}`,
        p_stocktake_id: stocktakeId,
        p_stocktake_line_id: stocktakeLineId,
        p_expected_line_version: lineVersion,
        p_reason: reason,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "review-recount"),
          lineVersion,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Line dikembalikan ke Counting untuk attempt setelah ${result.currentAttemptNo}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}


export async function approveStocktakeAction(formData: FormData) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const stocktakeVersion = requiredPositiveVersion(formData);
  const confirmation = formData.get("confirmation") === "on";

  let destination: string;

  try {
    const note =
      String(formData.get("note") ?? "").trim() || null;

    const result = await callRpc<StocktakeApprovalResponse>(
      "approve_stocktake",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key:
          `stocktake:${stocktakeId}:approve:${stocktakeVersion}`,
        p_stocktake_id: stocktakeId,
        p_expected_stocktake_version: stocktakeVersion,
        p_confirmation: confirmation,
        p_note: note,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "approve"),
          stocktakeVersion,
        },
      },
    );

    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Stocktake disetujui sebagai approval version ${result.approvalVersion}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}
export async function postStocktakeAdjustmentAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const stocktakeId = requiredUuid(formData, "stocktakeId");
  const approvalVersionRaw = required(
    formData,
    "approvalVersion",
  );

  if (!/^\d+$/.test(approvalVersionRaw)) {
    throw new Error("STOCKTAKE_APPROVAL_VERSION_REQUIRED");
  }

  const approvalVersion = Number(approvalVersionRaw);

  if (
    !Number.isSafeInteger(approvalVersion) ||
    approvalVersion <= 0
  ) {
    throw new Error("STOCKTAKE_APPROVAL_VERSION_REQUIRED");
  }

  const confirmation =
    formData.get("confirmation") === "on";

  let destination: string;

  try {
    const note =
      String(formData.get("note") ?? "").trim() || null;
    const idempotencyKey = stocktakePostingIdempotencyKey(
      stocktakeId,
      approvalVersion,
    );

    const result = await callRpc<StocktakePostingResponse>(
      "post_stocktake_adjustment",
      {
        p_organization_id: session.profile.organization_id,
        p_idempotency_key: idempotencyKey,
        p_stocktake_id: stocktakeId,
        p_approval_version: approvalVersion,
        p_confirmation: confirmation,
        p_note: note,
        p_metadata: {
          ...lifecycleMetadata(session.user.id, "post"),
          approvalVersion,
        },
      },
    );

    revalidatePath("/");
    revalidatePath("/reconciliation");
    revalidatePath("/stocktakes");
    revalidatePath(`/stocktakes/${stocktakeId}`);

    destination = detailDestination(
      stocktakeId,
      "success",
      `Adjustment ${result.transactionNo} berhasil diposting. Reconciliation ${result.reconciliationIntegrityStatus}.`,
    );
  } catch (error) {
    destination = detailDestination(
      stocktakeId,
      "error",
      stocktakeErrorMessage(error),
    );
  }

  redirect(destination);
}
