import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakePosting,
  StocktakePostingLine,
  StocktakeVarianceReason,
} from "@/lib/stocktakes/types";

export type StocktakeAdjustmentPreview = {
  positiveLineCount: number;
  negativeLineCount: number;
  zeroLineCount: number;
  unitsAdded: number;
  unitsRemoved: number;
  netAdjustmentQty: number;
  totalAbsoluteAdjustmentQty: number;
  reasonDistribution: Array<{
    reasonCode: StocktakeVarianceReason;
    lineCount: number;
    totalAbsoluteQty: number;
  }>;
};

export type StocktakeSnapshotIntegrityIssue =
  | "EMPTY_SNAPSHOT"
  | "LINE_COUNT_MISMATCH"
  | "NONZERO_LINE_COUNT_MISMATCH"
  | "NET_ADJUSTMENT_MISMATCH"
  | "ABSOLUTE_ADJUSTMENT_MISMATCH"
  | "SNAPSHOT_IDENTITY_MISMATCH"
  | "DUPLICATE_LINE_IDENTITY";

export type StocktakeSnapshotIntegrity = {
  isValid: boolean;
  issues: StocktakeSnapshotIntegrityIssue[];
  expectedLineCount: number;
  actualLineCount: number;
  expectedNonzeroLineCount: number;
  actualNonzeroLineCount: number;
  expectedNetAdjustmentQty: number;
  actualNetAdjustmentQty: number;
  expectedTotalAbsoluteAdjustmentQty: number | null;
  actualTotalAbsoluteAdjustmentQty: number;
};

function duplicateIdentityExists(values: string[]) {
  return new Set(values).size !== values.length;
}

export function evaluateStocktakeApprovalSnapshot(
  approval: StocktakeApproval,
  lines: StocktakeApprovalLine[],
): StocktakeSnapshotIntegrity {
  const expectedLineCount = Number(approval.line_count);
  const actualLineCount = lines.length;
  const expectedNonzeroLineCount = Number(approval.variance_line_count);
  const actualNonzeroLineCount = lines.filter(
    (line) => Number(line.variance_qty) !== 0,
  ).length;
  const expectedNetAdjustmentQty = Number(approval.total_variance_qty);
  const actualNetAdjustmentQty = lines.reduce(
    (total, line) => total + Number(line.variance_qty),
    0,
  );
  const actualTotalAbsoluteAdjustmentQty = lines.reduce(
    (total, line) => total + Math.abs(Number(line.variance_qty)),
    0,
  );
  const identityMatches = lines.every(
    (line) =>
      line.approval_id === approval.approval_id &&
      line.stocktake_id === approval.stocktake_id,
  );
  const duplicateIdentity =
    duplicateIdentityExists(lines.map((line) => line.approval_line_id)) ||
    duplicateIdentityExists(lines.map((line) => line.stocktake_line_id));

  const issues: StocktakeSnapshotIntegrityIssue[] = [];

  if (expectedLineCount <= 0) {
    issues.push("EMPTY_SNAPSHOT");
  }
  if (actualLineCount !== expectedLineCount) {
    issues.push("LINE_COUNT_MISMATCH");
  }
  if (actualNonzeroLineCount !== expectedNonzeroLineCount) {
    issues.push("NONZERO_LINE_COUNT_MISMATCH");
  }
  if (actualNetAdjustmentQty !== expectedNetAdjustmentQty) {
    issues.push("NET_ADJUSTMENT_MISMATCH");
  }
  if (!identityMatches) {
    issues.push("SNAPSHOT_IDENTITY_MISMATCH");
  }
  if (duplicateIdentity) {
    issues.push("DUPLICATE_LINE_IDENTITY");
  }

  return {
    isValid: issues.length === 0,
    issues,
    expectedLineCount,
    actualLineCount,
    expectedNonzeroLineCount,
    actualNonzeroLineCount,
    expectedNetAdjustmentQty,
    actualNetAdjustmentQty,
    expectedTotalAbsoluteAdjustmentQty: null,
    actualTotalAbsoluteAdjustmentQty,
  };
}

export function evaluateStocktakePostingSnapshot(
  posting: StocktakePosting,
  lines: StocktakePostingLine[],
): StocktakeSnapshotIntegrity {
  const expectedLineCount = Number(posting.line_count);
  const actualLineCount = lines.length;
  const expectedNonzeroLineCount = Number(posting.nonzero_line_count);
  const actualNonzeroLineCount = lines.filter(
    (line) => Number(line.adjustment_qty) !== 0,
  ).length;
  const expectedNetAdjustmentQty = Number(posting.net_adjustment_qty);
  const actualNetAdjustmentQty = lines.reduce(
    (total, line) => total + Number(line.adjustment_qty),
    0,
  );
  const expectedTotalAbsoluteAdjustmentQty = Number(
    posting.total_absolute_adjustment_qty,
  );
  const actualTotalAbsoluteAdjustmentQty = lines.reduce(
    (total, line) => total + Math.abs(Number(line.adjustment_qty)),
    0,
  );
  const identityMatches = lines.every(
    (line) =>
      line.posting_id === posting.posting_id &&
      line.stocktake_id === posting.stocktake_id,
  );
  const duplicateIdentity =
    duplicateIdentityExists(lines.map((line) => line.posting_line_id)) ||
    duplicateIdentityExists(lines.map((line) => line.stocktake_line_id));

  const issues: StocktakeSnapshotIntegrityIssue[] = [];

  if (expectedLineCount <= 0) {
    issues.push("EMPTY_SNAPSHOT");
  }
  if (actualLineCount !== expectedLineCount) {
    issues.push("LINE_COUNT_MISMATCH");
  }
  if (actualNonzeroLineCount !== expectedNonzeroLineCount) {
    issues.push("NONZERO_LINE_COUNT_MISMATCH");
  }
  if (actualNetAdjustmentQty !== expectedNetAdjustmentQty) {
    issues.push("NET_ADJUSTMENT_MISMATCH");
  }
  if (
    actualTotalAbsoluteAdjustmentQty !==
    expectedTotalAbsoluteAdjustmentQty
  ) {
    issues.push("ABSOLUTE_ADJUSTMENT_MISMATCH");
  }
  if (!identityMatches) {
    issues.push("SNAPSHOT_IDENTITY_MISMATCH");
  }
  if (duplicateIdentity) {
    issues.push("DUPLICATE_LINE_IDENTITY");
  }

  return {
    isValid: issues.length === 0,
    issues,
    expectedLineCount,
    actualLineCount,
    expectedNonzeroLineCount,
    actualNonzeroLineCount,
    expectedNetAdjustmentQty,
    actualNetAdjustmentQty,
    expectedTotalAbsoluteAdjustmentQty,
    actualTotalAbsoluteAdjustmentQty,
  };
}

export function stocktakePostingIdempotencyKey(
  stocktakeId: string,
  approvalVersion: number,
) {
  return `stocktake:${stocktakeId}:post:${approvalVersion}`;
}

export function buildStocktakeAdjustmentPreview(
  lines: StocktakeApprovalLine[],
): StocktakeAdjustmentPreview {
  let positiveLineCount = 0;
  let negativeLineCount = 0;
  let zeroLineCount = 0;
  let unitsAdded = 0;
  let unitsRemoved = 0;
  let netAdjustmentQty = 0;
  let totalAbsoluteAdjustmentQty = 0;

  const reasons = new Map<
    StocktakeVarianceReason,
    { lineCount: number; totalAbsoluteQty: number }
  >();

  for (const line of lines) {
    const variance = Number(line.variance_qty);
    const absolute = Math.abs(variance);

    netAdjustmentQty += variance;
    totalAbsoluteAdjustmentQty += absolute;

    if (variance > 0) {
      positiveLineCount += 1;
      unitsAdded += variance;
    } else if (variance < 0) {
      negativeLineCount += 1;
      unitsRemoved += absolute;
    } else {
      zeroLineCount += 1;
    }

    if (variance !== 0 && line.reason_code) {
      const existing = reasons.get(line.reason_code) ?? {
        lineCount: 0,
        totalAbsoluteQty: 0,
      };

      reasons.set(line.reason_code, {
        lineCount: existing.lineCount + 1,
        totalAbsoluteQty:
          existing.totalAbsoluteQty + absolute,
      });
    }
  }

  return {
    positiveLineCount,
    negativeLineCount,
    zeroLineCount,
    unitsAdded,
    unitsRemoved,
    netAdjustmentQty,
    totalAbsoluteAdjustmentQty,
    reasonDistribution: Array.from(reasons.entries())
      .map(([reasonCode, summary]) => ({
        reasonCode,
        ...summary,
      }))
      .sort(
        (left, right) =>
          right.totalAbsoluteQty - left.totalAbsoluteQty ||
          left.reasonCode.localeCompare(right.reasonCode),
      ),
  };
}