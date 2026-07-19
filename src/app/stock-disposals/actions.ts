"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  parseStockDisposalDraft,
  serializeStockDisposalDraft,
  stockDisposalErrorMessage,
  stockDisposalOccurredAt,
  type StockDisposalDraft,
} from "@/app/stock-disposals/draft";
import { requireAdminSession } from "@/lib/auth";
import { postStockDisposal } from "@/lib/supabase-rest";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key.toUpperCase()}_REQUIRED`);
  }

  return value.trim();
}

function draftFromForm(formData: FormData) {
  return parseStockDisposalDraft(required(formData, "draft"));
}

function previewDestination(draft?: StockDisposalDraft, error?: string) {
  const params = new URLSearchParams();

  if (draft) {
    params.set("draft", serializeStockDisposalDraft(draft));
  }

  if (error) {
    params.set("error", error);
  }

  const query = params.toString();
  return `/stock-disposals${query ? `?${query}` : ""}#${
    error ? "draft" : "preview"
  }`;
}

function resultDestination(
  kind: "success" | "error",
  message: string,
  options: {
    draft?: StockDisposalDraft;
    disposalId?: string;
    transactionId?: string;
  } = {},
) {
  const params = new URLSearchParams({ [kind]: message });

  if (kind === "error" && options.draft) {
    params.set("draft", serializeStockDisposalDraft(options.draft));
  }

  if (options.disposalId) {
    params.set("disposalId", options.disposalId);
  }

  if (options.transactionId) {
    params.set("transactionId", options.transactionId);
  }

  return `/stock-disposals?${params.toString()}#${
    kind === "success" ? "history" : "preview"
  }`;
}

export async function previewStockDisposalAction(formData: FormData) {
  await requireAdminSession();

  let destination: string;

  try {
    const draft = draftFromForm(formData);
    destination = previewDestination(draft);
  } catch (error) {
    destination = previewDestination(
      undefined,
      stockDisposalErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function postStockDisposalAction(formData: FormData) {
  const session = await requireAdminSession();
  let draft: StockDisposalDraft | undefined;
  let destination: string;

  try {
    draft = draftFromForm(formData);

    const previewBasisHash = required(
      formData,
      "previewBasisHash",
    ).toLowerCase();

    if (!SHA256_PATTERN.test(previewBasisHash)) {
      throw new Error("STOCK_DISPOSAL_PREVIEW_HASH_INVALID");
    }

    const intentId = required(formData, "intentId");

    if (!UUID_PATTERN.test(intentId)) {
      throw new Error("IDEMPOTENCY_KEY_REQUIRED");
    }

    if (formData.get("confirmation") !== "on") {
      throw new Error("STOCK_DISPOSAL_CONFIRMATION_REQUIRED");
    }

    const result = await postStockDisposal({
      organizationId: session.profile.organization_id,
      idempotencyKey: `stock-disposal:${intentId}`,
      previewBasisHash,
      confirmation: true,
      sourceRef: draft.sourceRef,
      occurredAt: stockDisposalOccurredAt(draft),
      reasonCode: draft.reasonCode,
      lines: draft.lines,
      referenceText: draft.referenceText,
      note: draft.note,
      metadata: {
        source: "stock-disposal-admin-ui",
        version: 1,
      },
    });

    revalidatePath("/");
    revalidatePath("/stock-disposals");
    revalidatePath("/entry-corrections");
    revalidatePath("/notifications");
    revalidatePath("/reconciliation");

    destination = resultDestination(
      "success",
      `${result.disposalNo} berhasil memusnahkan ${result.totalQuantity} unit dari ${result.lineCount} baris batch.`,
      {
        disposalId: result.disposalId,
        transactionId: result.transactionId,
      },
    );
  } catch (error) {
    destination = resultDestination(
      "error",
      stockDisposalErrorMessage(error),
      { draft },
    );
  }

  redirect(destination);
}