"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  marketplaceCancellationErrorMessage,
  marketplaceCancellationHasPostShipment,
  marketplaceCancellationOccurredAt,
  parseMarketplaceCancellationDraft,
  serializeMarketplaceCancellationDraft,
  type MarketplaceCancellationDraft,
} from "@/app/marketplace/cancellations/draft";
import { requireAdminSession } from "@/lib/auth";
import { safeInternalRoute } from "@/lib/safe-internal-route";
import { postMarketplaceCancellation } from "@/lib/supabase-rest";

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

function optionalOrderId(formData: FormData) {
  const value = String(formData.get("orderId") ?? "").trim();
  return UUID_PATTERN.test(value) ? value : null;
}

function draftFromForm(formData: FormData) {
  return parseMarketplaceCancellationDraft(required(formData, "draft"));
}

function resultDestination(
  kind: "success" | "error",
  message: string,
  options: {
    draft?: MarketplaceCancellationDraft;
    cancellationId?: string;
    eventId?: string;
    transactionId?: string | null;
    orderId?: string | null;
    returnTo?: string;
  } = {},
) {
  const params = new URLSearchParams({ [kind]: message });

  if (kind === "error" && options.draft) {
    params.set(
      "cancellationDraft",
      serializeMarketplaceCancellationDraft(options.draft),
    );
  }

  if (options.cancellationId) {
    params.set("cancellationId", options.cancellationId);
  }

  if (options.eventId) {
    params.set("cancellationEventId", options.eventId);
  }

  if (options.transactionId) {
    params.set("transactionId", options.transactionId);
  }

  if (options.returnTo && options.returnTo !== "/marketplace") {
    params.set("returnTo", options.returnTo);
  }

  const basePath = options.orderId
    ? `/marketplace/${encodeURIComponent(options.orderId)}`
    : "/marketplace";

  return `${basePath}?${params.toString()}#${
    kind === "success" ? "cancellation-history" : "cancellation-preview"
  }`;
}

export async function postMarketplaceCancellationAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const orderId = optionalOrderId(formData);
  const returnTo = safeInternalRoute(
    String(formData.get("returnTo") ?? ""),
    "/marketplace",
    { allowedPathnames: ["/marketplace"] },
  );
  let draft: MarketplaceCancellationDraft | undefined;
  let destination: string;

  try {
    draft = draftFromForm(formData);

    const previewBasisHash = required(
      formData,
      "previewBasisHash",
    ).toLowerCase();

    if (!SHA256_PATTERN.test(previewBasisHash)) {
      throw new Error("MARKETPLACE_CANCELLATION_PREVIEW_HASH_INVALID");
    }

    const intentId = required(formData, "intentId");

    if (!UUID_PATTERN.test(intentId)) {
      throw new Error("IDEMPOTENCY_KEY_REQUIRED");
    }

    const requiresConfirmation =
      marketplaceCancellationHasPostShipment(draft);
    const confirmation = formData.get("confirmation") === "on";

    if (requiresConfirmation && !confirmation) {
      throw new Error("MARKETPLACE_CANCELLATION_CONFIRMATION_REQUIRED");
    }

    const result = await postMarketplaceCancellation({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-cancellation:${intentId}`,
      previewBasisHash,
      confirmation,
      channelCode: draft.channelCode,
      eventRef: draft.eventRef,
      orderRef: draft.orderRef,
      occurredAt: marketplaceCancellationOccurredAt(draft),
      sourceStatus: draft.sourceStatus,
      lines: draft.lines,
      note: draft.note,
      metadata: {
        source: "marketplace-cancellation-admin-ui",
        version: 1,
      },
    });

    revalidatePath("/");
    revalidatePath("/marketplace");
    if (orderId) {
      revalidatePath(`/marketplace/${orderId}`);
    }
    revalidatePath("/returns");
    revalidatePath("/entry-corrections");
    revalidatePath("/notifications");
    revalidatePath("/reconciliation");

    const stockEffect =
      result.postShipmentQuantity > 0
        ? `${result.postShipmentQuantity} unit dikembalikan ke batch kiriman asal. Sistem mencatat pembalikannya untuk jejak audit.`
        : `${result.preShipmentQuantity} unit dilepas dari reservasi. Stok fisik tidak berubah.`;

    destination = resultDestination(
      "success",
      `${result.cancellationNo} berhasil membatalkan ${result.totalQuantity} unit. ${stockEffect}`,
      {
        cancellationId: result.cancellationId,
        eventId: result.eventId,
        transactionId: result.singleReversalTransactionId,
        orderId: result.orderId ?? orderId,
        returnTo,
      },
    );
  } catch (error) {
    destination = resultDestination(
      "error",
      marketplaceCancellationErrorMessage(error),
      { draft, orderId, returnTo },
    );
  }

  redirect(destination);
}
