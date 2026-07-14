"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import { callRpc } from "@/lib/supabase-rest";
import { stocktakeErrorMessage } from "@/lib/stocktakes/errors";
import {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
  type StocktakeBucket,
  type StocktakeCreateResponse,
  type StocktakeScopeDefinition,
  type StocktakeScopeMode,
  type StocktakeType,
  type StocktakeVisibility,
} from "@/lib/stocktakes/types";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
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

    const success = new URLSearchParams({
      success: `${result.stocktakeNo} berhasil dibuat sebagai Draft.`,
    });

    destination = `/stocktakes/${result.stocktakeId}?${success.toString()}`;
  } catch (error) {
    const errorParams = new URLSearchParams({
      idempotencyKey,
      error: stocktakeErrorMessage(error),
    });

    destination = `/stocktakes/new?${errorParams.toString()}`;
  }

  redirect(destination);
}