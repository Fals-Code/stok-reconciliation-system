"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  jakartaTimestamp,
  marketplaceListingAdminErrorMessage,
  parseMarketplaceListingChannel,
  parseMarketplaceListingComponents,
  parseMarketplaceListingType,
} from "@/app/marketplace/listings/draft";
import { requireAdminSession } from "@/lib/auth";
import {
  activateMarketplaceListingVersion,
  archiveMarketplaceListing,
  createMarketplaceListingVersionDraft,
  retireMarketplaceListingVersion,
  saveMarketplaceListingVersionDraft,
} from "@/lib/supabase-rest";

type FeedbackKind = "success" | "error";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function optional(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function positiveInteger(formData: FormData, key: string) {
  const value = Number(required(formData, key));

  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${key} harus berupa bilangan bulat positif.`);
  }

  return value;
}

function requiredConfirmation(formData: FormData, code: string) {
  if (formData.get("confirmation") !== "on") {
    throw new Error(code);
  }
}

function destination(
  kind: FeedbackKind,
  message: string,
  options: {
    listingId?: string | null;
    versionId?: string | null;
    preview?: boolean;
  } = {},
) {
  const params = new URLSearchParams({ [kind]: message });

  if (options.listingId) {
    params.set("selectedListingId", options.listingId);
  }

  if (options.versionId) {
    params.set("selectedVersionId", options.versionId);
  }

  if (options.preview && options.listingId && options.versionId) {
    params.set("previewListingId", options.listingId);
    params.set("previewVersionId", options.versionId);
  }

  const anchor = options.preview
    ? "activation-preview"
    : options.versionId
      ? "version-detail"
      : "listing-catalog";

  return `/marketplace/listings?${params.toString()}#${anchor}`;
}

function revalidateMarketplaceListings() {
  revalidatePath("/marketplace");
  revalidatePath("/marketplace/listings");
}

function mappingInput(formData: FormData) {
  const listingTypeCode = parseMarketplaceListingType(
    required(formData, "listingTypeCode"),
  );
  const productId =
    listingTypeCode === "SINGLE" ? required(formData, "productId") : null;
  const components =
    listingTypeCode === "BUNDLE"
      ? parseMarketplaceListingComponents(required(formData, "components"))
      : [];

  if (listingTypeCode === "BUNDLE" && components.length === 0) {
    throw new Error("MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED");
  }

  return { listingTypeCode, productId, components };
}

export async function createMarketplaceListingDraftAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  let redirectTo: string;

  try {
    const intentId = required(formData, "intentId");
    const channelCode = parseMarketplaceListingChannel(
      required(formData, "channelCode"),
    );
    const externalListingCode = required(formData, "externalListingCode");
    const displayName = required(formData, "displayName");
    const effectiveFrom = jakartaTimestamp(
      required(formData, "effectiveFrom"),
    );
    const note = optional(formData, "note");
    const { listingTypeCode, productId, components } =
      mappingInput(formData);

    const result = await createMarketplaceListingVersionDraft({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-admin:create:${intentId}`,
      channelCode,
      externalListingCode,
      displayName,
      listingTypeCode,
      effectiveFrom,
      productId,
      components,
      note,
      metadata: {
        source: "marketplace-listing-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    revalidateMarketplaceListings();
    redirectTo = destination(
      "success",
      `${externalListingCode} versi ${result.version} disimpan sebagai draft tanpa dampak stok.`,
      {
        listingId: result.listingId,
        versionId: result.versionId,
      },
    );
  } catch (error) {
    redirectTo = destination(
      "error",
      marketplaceListingAdminErrorMessage(error),
    );
  }

  redirect(redirectTo);
}

export async function saveMarketplaceListingDraftAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const listingId = optional(formData, "listingId");
  const versionId = optional(formData, "versionId");
  let redirectTo: string;

  try {
    if (!listingId || !versionId) {
      throw new Error("MARKETPLACE_LISTING_VERSION_REQUIRED");
    }

    const displayName = required(formData, "displayName");
    const effectiveFrom = jakartaTimestamp(
      required(formData, "effectiveFrom"),
    );
    const expectedRowVersion = positiveInteger(
      formData,
      "expectedRowVersion",
    );
    const note = optional(formData, "note");
    const { productId, components } = mappingInput(formData);

    const result = await saveMarketplaceListingVersionDraft({
      organizationId: session.profile.organization_id,
      listingId,
      versionId,
      expectedRowVersion,
      displayName,
      effectiveFrom,
      productId,
      components,
      note,
      metadata: {
        source: "marketplace-listing-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    revalidateMarketplaceListings();
    redirectTo = destination(
      "success",
      `Draft disimpan dengan row version ${result.versionRowVersion}.`,
      { listingId, versionId },
    );
  } catch (error) {
    redirectTo = destination(
      "error",
      marketplaceListingAdminErrorMessage(error),
      { listingId, versionId },
    );
  }

  redirect(redirectTo);
}

export async function activateMarketplaceListingVersionAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const listingId = optional(formData, "listingId");
  const versionId = optional(formData, "versionId");
  let redirectTo: string;

  try {
    if (!listingId || !versionId) {
      throw new Error("MARKETPLACE_LISTING_VERSION_REQUIRED");
    }

    requiredConfirmation(
      formData,
      "MARKETPLACE_LISTING_ACTIVATION_CONFIRMATION_REQUIRED",
    );

    const intentId = required(formData, "intentId");
    const expectedRowVersion = positiveInteger(
      formData,
      "expectedRowVersion",
    );
    const previewBasisHash = required(
      formData,
      "previewBasisHash",
    ).toLowerCase();

    if (!/^[0-9a-f]{64}$/.test(previewBasisHash)) {
      throw new Error("MARKETPLACE_LISTING_PREVIEW_HASH_INVALID");
    }

    const result = await activateMarketplaceListingVersion({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-admin:activate:${intentId}`,
      listingId,
      versionId,
      expectedRowVersion,
      previewBasisHash,
      confirmation: true,
    });

    revalidateMarketplaceListings();
    redirectTo = destination(
      "success",
      `Versi ${result.version} aktif mulai ${new Intl.DateTimeFormat(
        "id-ID",
        {
          timeZone: "Asia/Jakarta",
          dateStyle: "medium",
          timeStyle: "short",
        },
      ).format(new Date(result.effectiveFrom))}.`,
      { listingId, versionId },
    );
  } catch (error) {
    redirectTo = destination(
      "error",
      marketplaceListingAdminErrorMessage(error),
      { listingId, versionId, preview: true },
    );
  }

  redirect(redirectTo);
}

export async function retireMarketplaceListingVersionAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const listingId = optional(formData, "listingId");
  const versionId = optional(formData, "versionId");
  let redirectTo: string;

  try {
    if (!listingId || !versionId) {
      throw new Error("MARKETPLACE_LISTING_VERSION_REQUIRED");
    }

    requiredConfirmation(
      formData,
      "MARKETPLACE_LISTING_RETIREMENT_CONFIRMATION_REQUIRED",
    );

    const intentId = required(formData, "intentId");
    const expectedRowVersion = positiveInteger(
      formData,
      "expectedRowVersion",
    );
    const effectiveTo = jakartaTimestamp(required(formData, "effectiveTo"));

    const result = await retireMarketplaceListingVersion({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-admin:retire:${intentId}`,
      listingId,
      versionId,
      expectedRowVersion,
      effectiveTo,
      confirmation: true,
    });

    revalidateMarketplaceListings();
    redirectTo = destination(
      "success",
      `Versi ${result.version} dijadwalkan berhenti tanpa menghapus histori order.`,
      { listingId, versionId },
    );
  } catch (error) {
    redirectTo = destination(
      "error",
      marketplaceListingAdminErrorMessage(error),
      { listingId, versionId },
    );
  }

  redirect(redirectTo);
}

export async function archiveMarketplaceListingAction(
  formData: FormData,
) {
  const session = await requireAdminSession();
  const listingId = optional(formData, "listingId");
  let redirectTo: string;

  try {
    if (!listingId) {
      throw new Error("MARKETPLACE_LISTING_NOT_FOUND");
    }

    requiredConfirmation(
      formData,
      "MARKETPLACE_LISTING_ARCHIVE_CONFIRMATION_REQUIRED",
    );

    const intentId = required(formData, "intentId");
    const expectedRowVersion = positiveInteger(
      formData,
      "expectedRowVersion",
    );

    const result = await archiveMarketplaceListing({
      organizationId: session.profile.organization_id,
      idempotencyKey: `marketplace-listing-admin:archive:${intentId}`,
      listingId,
      expectedRowVersion,
      confirmation: true,
    });

    revalidateMarketplaceListings();
    redirectTo = destination(
      "success",
      `${result.externalListingCode} diarsipkan. Snapshot order lama tetap dapat diaudit.`,
      { listingId },
    );
  } catch (error) {
    redirectTo = destination(
      "error",
      marketplaceListingAdminErrorMessage(error),
      { listingId },
    );
  }

  redirect(redirectTo);
}