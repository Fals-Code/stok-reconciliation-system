import type {
  StocktakeApprovalLine,
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