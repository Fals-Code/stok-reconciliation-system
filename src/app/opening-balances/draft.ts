export type OpeningBalanceBucketCode =
  | "SELLABLE"
  | "QUARANTINE"
  | "DAMAGED";

export type OpeningBalanceDraftLine = {
  productId: string;
  batchId: string;
  bucketCode: OpeningBalanceBucketCode;
  quantity: number;
  batchIdentityVerified: boolean;
  exceptionReference: string | null;
  sourceLineRef: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function emptyOpeningBalanceLine(index = 0): OpeningBalanceDraftLine {
  return {
    productId: "",
    batchId: "",
    bucketCode: "SELLABLE",
    quantity: 0,
    batchIdentityVerified: true,
    exceptionReference: null,
    sourceLineRef: `UI-${index + 1}`,
  };
}

export function openingBalanceTimestamp(raw: string) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(raw)) {
    throw new Error("OPENING_BALANCE_CUTOVER_AT_REQUIRED");
  }

  return `${raw}:00+07:00`;
}

export function parseOpeningBalanceLines(
  raw: string,
): OpeningBalanceDraftLine[] {
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("OPENING_BALANCE_LINES_MUST_BE_ARRAY");
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error("OPENING_BALANCE_LINES_REQUIRED");
  }

  if (parsed.length > 500) {
    throw new Error("OPENING_BALANCE_LINES_LIMIT_EXCEEDED");
  }

  const lines = parsed.map((value, index) => {
    if (!value || typeof value !== "object") {
      throw new Error("OPENING_BALANCE_LINE_INVALID");
    }

    const row = value as Record<string, unknown>;
    const productId = String(row.productId ?? "").trim();
    const batchId = String(row.batchId ?? "").trim();
    const bucketCode = String(row.bucketCode ?? "")
      .trim()
      .toUpperCase() as OpeningBalanceBucketCode;
    const quantity = Number(row.quantity);
    const sourceLineRef = String(row.sourceLineRef ?? "").trim();
    const batchIdentityVerified = row.batchIdentityVerified !== false;
    const exceptionReferenceRaw = String(
      row.exceptionReference ?? "",
    ).trim();
    const exceptionReference = exceptionReferenceRaw || null;

    if (
      !UUID_PATTERN.test(productId) ||
      !UUID_PATTERN.test(batchId) ||
      !new Set(["SELLABLE", "QUARANTINE", "DAMAGED"]).has(bucketCode) ||
      !Number.isSafeInteger(quantity) ||
      quantity < 0 ||
      quantity > 999_999_999 ||
      sourceLineRef.length === 0 ||
      sourceLineRef.length > 100
    ) {
      throw new Error(`OPENING_BALANCE_LINE_INVALID:${index + 1}`);
    }

    if (
      !batchIdentityVerified &&
      (bucketCode !== "QUARANTINE" || !exceptionReference)
    ) {
      throw new Error("UNKNOWN_BATCH_NOT_QUARANTINED");
    }

    if (batchIdentityVerified && exceptionReference) {
      throw new Error(
        "OPENING_BALANCE_VERIFIED_BATCH_EXCEPTION_FORBIDDEN",
      );
    }

    if (exceptionReference && exceptionReference.length > 200) {
      throw new Error(
        "OPENING_BALANCE_EXCEPTION_REFERENCE_TOO_LONG",
      );
    }

    return {
      productId,
      batchId,
      bucketCode,
      quantity,
      batchIdentityVerified,
      exceptionReference,
      sourceLineRef,
    };
  });

  const stockKeys = new Set<string>();
  const sourceRefs = new Set<string>();

  for (const line of lines) {
    const stockKey =
      `${line.productId}:${line.batchId}:${line.bucketCode}`.toLowerCase();

    if (stockKeys.has(stockKey)) {
      throw new Error("OPENING_BALANCE_DUPLICATE_BATCH_BUCKET_LINE");
    }

    if (sourceRefs.has(line.sourceLineRef)) {
      throw new Error("OPENING_BALANCE_DUPLICATE_SOURCE_LINE");
    }

    stockKeys.add(stockKey);
    sourceRefs.add(line.sourceLineRef);
  }

  return lines;
}
