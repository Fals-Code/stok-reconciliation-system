"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  manualOutboundErrorMessage,
  manualOutboundOccurredAt,
  parseManualOutboundDraft,
  serializeManualOutboundDraft,
  type ManualOutboundDraft,
} from "@/app/manual-outbounds/draft";
import { requireAdminSession } from "@/lib/auth";
import { postManualOutbound } from "@/lib/supabase-rest";

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
  return parseManualOutboundDraft(required(formData, "draft"));
}

function previewDestination(draft?: ManualOutboundDraft, error?: string) {
  const params = new URLSearchParams();

  if (draft) {
    params.set("draft", serializeManualOutboundDraft(draft));
  }

  if (error) {
    params.set("error", error);
  }

  const query = params.toString();
  return `/manual-outbounds${query ? `?${query}` : ""}#${
    error ? "draft" : "preview"
  }`;
}

function resultDestination(
  kind: "success" | "error",
  message: string,
  options: {
    draft?: ManualOutboundDraft;
    outboundId?: string;
    transactionId?: string;
  } = {},
) {
  const params = new URLSearchParams({ [kind]: message });

  if (kind === "error" && options.draft) {
    params.set("draft", serializeManualOutboundDraft(options.draft));
  }

  if (options.outboundId) {
    params.set("outboundId", options.outboundId);
  }

  if (options.transactionId) {
    params.set("transactionId", options.transactionId);
  }

  return `/manual-outbounds?${params.toString()}#${
    kind === "success" ? "history" : "preview"
  }`;
}

export async function previewManualOutboundAction(formData: FormData) {
  await requireAdminSession();

  let destination: string;

  try {
    const draft = draftFromForm(formData);
    destination = previewDestination(draft);
  } catch (error) {
    destination = previewDestination(
      undefined,
      manualOutboundErrorMessage(error),
    );
  }

  redirect(destination);
}

export async function postManualOutboundAction(formData: FormData) {
  const session = await requireAdminSession();
  let draft: ManualOutboundDraft | undefined;
  let destination: string;

  try {
    draft = draftFromForm(formData);

    const previewBasisHash = required(
      formData,
      "previewBasisHash",
    ).toLowerCase();

    if (!SHA256_PATTERN.test(previewBasisHash)) {
      throw new Error("MANUAL_OUTBOUND_PREVIEW_HASH_INVALID");
    }

    const intentId = required(formData, "intentId");

    if (!UUID_PATTERN.test(intentId)) {
      throw new Error("IDEMPOTENCY_KEY_REQUIRED");
    }

    if (formData.get("confirmation") !== "on") {
      throw new Error("MANUAL_OUTBOUND_CONFIRMATION_REQUIRED");
    }

    const result = await postManualOutbound({
      organizationId: session.profile.organization_id,
      idempotencyKey: `manual-outbound:${intentId}`,
      previewBasisHash,
      confirmation: true,
      sourceRef: draft.sourceRef,
      occurredAt: manualOutboundOccurredAt(draft),
      reasonCode: draft.reasonCode,
      lines: draft.lines,
      note: draft.note,
      reference: draft.reference,
      metadata: {
        source: "manual-outbound-admin-ui",
        version: 1,
      },
    });

    revalidatePath("/");
    revalidatePath("/manual-outbounds");
    revalidatePath("/entry-corrections");
    revalidatePath("/reconciliation");

    destination = resultDestination(
      "success",
      `${result.outboundNo} berhasil memposting ${result.totalQuantity} unit melalui ${result.allocationCount} alokasi FEFO.`,
      {
        outboundId: result.outboundId,
        transactionId: result.transactionId,
      },
    );
  } catch (error) {
    destination = resultDestination(
      "error",
      manualOutboundErrorMessage(error),
      { draft },
    );
  }

  redirect(destination);
}
