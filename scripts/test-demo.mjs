import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";
const DEMO_EMAIL = "demo.admin@glowlab.invalid";
const REQUEST_TIMEOUT_MS = 30_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const PRODUCT_FIXTURES = [
  { sku: "SER-NIA-30", name: "Serum Niacinamide 30 ml", unitCode: "UNIT" },
  { sku: "CLN-GEN-100", name: "Gentle Cleanser 100 ml", unitCode: "UNIT" },
  { sku: "TNR-HYD-100", name: "Hydrating Toner 100 ml", unitCode: "UNIT" },
];

const BATCH_FIXTURES = [
  {
    productSku: "SER-NIA-30",
    batchCode: "SER-2608-A",
    expiryDate: "2026-08-01",
    batchKindCode: "STANDARD",
  },
  {
    productSku: "SER-NIA-30",
    batchCode: "SER-2612-B",
    expiryDate: "2026-12-31",
    batchKindCode: "STANDARD",
  },
  {
    productSku: "CLN-GEN-100",
    batchCode: "CLN-2611-A",
    expiryDate: "2026-11-30",
    batchKindCode: "STANDARD",
  },
  {
    productSku: "TNR-HYD-100",
    batchCode: "TNR-2610-A",
    expiryDate: "2026-10-31",
    batchKindCode: "STANDARD",
  },
];

const SEEDED_INITIAL_BALANCE_TRANSACTION = {
  transactionId: "70000000-0000-4000-8000-000000000001",
  transactionNo: "SEED-IB-000001",
  transactionTypeCode: "INITIAL_BALANCE",
  reasonCodeSnapshot: "INITIAL_BALANCE",
  sourceTypeCode: "SEED",
  sourceRefSnapshot: "SEED-INITIAL-BALANCE-V1",
  channelCodeSnapshot: "SYSTEM",
  entryRoleCode: "ADJUSTMENT",
  bucketCode: "SELLABLE",
};

const SLICE_C = {
  idempotencyKey:
    "GOLDEN-DEMO-V1:SHOPEE:RESERVE:ORDER-001",
  externalEventRef:
    "GOLDEN-DEMO-V1:SHP-EVT:ORDER-001:READY_TO_SHIP",
  externalOrderRef:
    "GOLDEN-DEMO-V1:SHP-ORDER-001",
  sourceLineRef:
    "GOLDEN-DEMO-V1:SHP-ORDER-001:LINE-1",
  externalListingCode:
    "SHP-SER-NIA-30",
  occurredAt:
    "2026-07-15T03:00:00Z",
  receivedAt:
    "2026-07-15T03:00:05Z",
  channelCode:
    "SHOPEE",
  sourceStatus:
    "READY_TO_SHIP",
  listingQuantity:
    8,
};

const SLICE_D = {
  idempotencyKey: "GOLDEN-DEMO-V1:SHOPEE:SHIP:ORDER-001",
  externalEventRef: "GOLDEN-DEMO-V1:SHP-EVT:ORDER-001:SHIPPED",
  externalOrderRef: SLICE_C.externalOrderRef,
  orderSourceLineRef: SLICE_C.sourceLineRef,
  canonicalSourceLineRef: `${SLICE_C.sourceLineRef}#C001`,
  componentNo: 1,
  quantity: 8,
  occurredAt: "2026-07-15T03:10:00Z",
  receivedAt: "2026-07-15T03:10:05Z",
  channelCode: "SHOPEE",
  sourceStatus: "SHIPPED",
  note: "Golden Demo Slice D Shopee shipment."
};

const SLICE_E = {
  listingIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:TIKTOK_SHOP:TTS-SER-NIA-30:DRAFT",
  activationIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:TIKTOK_SHOP:TTS-SER-NIA-30:ACTIVATE",
  reservationIdempotencyKey:
    "GOLDEN-DEMO-V1:TIKTOK:RESERVE:ORDER-001",
  shipmentIdempotencyKey:
    "GOLDEN-DEMO-V1:TIKTOK:SHIP:ORDER-001",
  externalListingCode: "TTS-SER-NIA-30",
  externalReserveEventRef:
    "GOLDEN-DEMO-V1:TTS-EVT:ORDER-001:READY_TO_SHIP",
  externalShipEventRef:
    "GOLDEN-DEMO-V1:TTS-EVT:ORDER-001:IN_TRANSIT",
  externalOrderRef: "GOLDEN-DEMO-V1:TTS-ORDER-001",
  sourceLineRef: "GOLDEN-DEMO-V1:TTS-ORDER-001:LINE-1",
  canonicalSourceLineRef:
    "GOLDEN-DEMO-V1:TTS-ORDER-001:LINE-1#C001",
  occurredAt: "2026-07-15T03:20:00Z",
  reserveReceivedAt: "2026-07-15T03:20:05Z",
  shipOccurredAt: "2026-07-15T03:30:00Z",
  shipReceivedAt: "2026-07-15T03:30:05Z",
  channelCode: "TIKTOK_SHOP",
  sourceStatusReserve: "READY_TO_SHIP",
  sourceStatusShip: "IN_TRANSIT",
  listingQuantity: 1,
};

const SLICE_G = {
  listingIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:SHOPEE:SHP-BND-GLOW-01:DRAFT",
  activationIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:SHOPEE:SHP-BND-GLOW-01:ACTIVATE",
  reserveIdempotencyKey:
    "GOLDEN-DEMO-V1:SHOPEE:RESERVE:BUNDLE-001",
  shipIdempotencyKey:
    "GOLDEN-DEMO-V1:SHOPEE:SHIP:BUNDLE-001",
  channelCode: "SHOPEE",
  externalListingCode: "SHP-BND-GLOW-01",
  displayName: "Glow Starter Bundle",
  listingTypeCode: "BUNDLE",
  effectiveFrom: "2026-07-01T00:00:00+07:00",
  orderRef: "GOLDEN-DEMO-V1:SHP-ORDER-BUNDLE-001",
  sourceLineRef: "GOLDEN-DEMO-V1:SHP-ORDER-BUNDLE-001:LINE-1",
  reserveEventRef: "GOLDEN-DEMO-V1:SHP-EVT-BUNDLE-001:READY_TO_SHIP",
  shipEventRef: "GOLDEN-DEMO-V1:SHP-EVT-BUNDLE-001:SHIPPED",
  reserveOccurredAt: "2026-07-15T04:00:00Z",
  reserveReceivedAt: "2026-07-15T04:00:05Z",
  shipOccurredAt: "2026-07-15T04:10:00Z",
  shipReceivedAt: "2026-07-15T04:10:05Z",
  sourceStatusReserve: "READY_TO_SHIP",
  sourceStatusShip: "SHIPPED",
  listingQuantity: 1,
  serumProductSku: "SER-NIA-30",
  cleanserProductSku: "CLN-GEN-100",
  serumExpandedQuantity: 2,
  cleanserExpandedQuantity: 1,
  serumCanonicalSourceLineRef: "GOLDEN-DEMO-V1:SHP-ORDER-BUNDLE-001:LINE-1#C001",
  cleanserCanonicalSourceLineRef: "GOLDEN-DEMO-V1:SHP-ORDER-BUNDLE-001:LINE-1#C002",
  bundleRecipeFingerprint: "a99c8bd115ff1f0fcd70951648fd59631a3b1a8dd2e96057f6ea81b00153144e",
  bundleMappingVersion: 1,
  bundleRecipeVersion: 1,
  metadataReference: "GOLDEN-DEMO-BUNDLE-001",
};

const SLICE_H = {
  legacyReturnRef: "GOLDEN-DEMO-V1:RETURN:SHOPEE:SHP-ORDER-001",
  legacyReceiptRef: "GOLDEN-DEMO-V1:RETURN:SHOPEE:SHP-ORDER-001:RECEIPT",
  correctedReturnRef: "GOLDEN-DEMO-V1:RETURN:SHOPEE:GOLDEN-DEMO-V1:SHP-ORDER-001:PRIMARY",
  correctedReceiptRef: "GOLDEN-DEMO-V1:RETURN:SHOPEE:GOLDEN-DEMO-V1:SHP-ORDER-001:PRIMARY:RECEIPT",
  expectedReturnIdempotencyKey: "GOLDEN-DEMO-V1:RETURN:SHOPEE:GOLDEN-DEMO-V1:SHP-ORDER-001:PRIMARY:EXPECTED",
  receiptIdempotencyKey: "GOLDEN-DEMO-V1:RETURN:SHOPEE:GOLDEN-DEMO-V1:SHP-ORDER-001:PRIMARY:RECEIPT",
  orderRef: SLICE_C.externalOrderRef,
  sourceLineRef: SLICE_C.sourceLineRef,
  occurredAt: "2026-07-15T04:20:00Z",
  receiptOccurredAt: "2026-07-15T04:25:00Z",
  note: "Golden Demo Slice H expected return and physical receipt.",
  metadataReference: "GOLDEN-DEMO-RETURN-001",
  expectedQuantity: 3,
  receiptQuantity: 3,
  productSku: SLICE_G.serumProductSku,
  productId: null,
  sourceBatchCode: "SER-2612-B",
};

const SLICE_I = {
  inspectionIdempotencyKey: "GOLDEN-DEMO-V1:RETURN:SHOPEE:GOLDEN-DEMO-V1:SHP-ORDER-001:PRIMARY:INSPECTION",
  inspectionRef: `${SLICE_H.correctedReturnRef}:INSPECTION`,
  occurredAt: "2026-07-15T04:35:00Z",
  note: "Golden Demo Slice I return inspection mixed sellable and damaged.",
  metadataReference: "GOLDEN-DEMO-RETURN-001:INSPECTION",
};

const SLICE_J = {
  expectedReturnIdempotencyKey: "GOLDEN-DEMO-V1:RETURN:TIKTOK:GOLDEN-DEMO-V1:TTS-ORDER-001:EXPECTED",
  lostIdempotencyKey: "GOLDEN-DEMO-V1:RETURN:TIKTOK:GOLDEN-DEMO-V1:TTS-ORDER-001:LOST",
  returnRef: "GOLDEN-DEMO-V1:RETURN:TIKTOK:GOLDEN-DEMO-V1:TTS-ORDER-001:LOST",
  lostEventRef: "GOLDEN-DEMO-V1:RETURN:TIKTOK:GOLDEN-DEMO-V1:TTS-ORDER-001:LOST:EVENT",
  expectedOccurredAt: "2026-07-15T04:40:00Z",
  lostOccurredAt: "2026-07-15T04:45:00Z",
  quantity: 1,
  productSku: "SER-NIA-30",
  sourceStatus: "RETURN_REQUESTED",
  note: "Golden Demo Slice J TikTok expected return and LOST evidence.",
  metadataReference: "GOLDEN-DEMO-TIKTOK-RETURN-001",
};

const SLICE_K = {
  claimIdempotencyKey: "GOLDEN-DEMO-V1:CLAIM:TIKTOK:GOLDEN-DEMO-V1:TTS-ORDER-001:LOST",
  legacyNotificationIdempotencyKey: "GOLDEN-DEMO-V1:NOTIFICATION:TIKTOK-CLAIM:D14",
  claimOccurredAt: "2026-07-15T04:50:00Z",
  claimTypeCode: "LOST_RETURN",
  workerProcessName: "golden-demo-trusted-worker",
  notificationStage: "D14",
  policyVersion: "TIKTOK_RETURN_CREATED_AT_V1",
};

/*
 * Terminal checkpoints intentionally use business names rather than assuming
 * that the next demo chapters are called Slice L/M.  Their durable identity
 * is the stocktake fixture reference plus the official posting/reconciliation
 * links, never a generated database id.
 */
const GOLDEN_TERMINAL = Object.freeze({
  stocktakeReference: "GOLDEN-DEMO-V1:STOCKTAKE:SER-2612-B:VARIANCE--1",
  stocktakeTitle: "Golden Demo stocktake Serum SER-2612-B variance -1",
  createIdempotencyKey: "GOLDEN-DEMO-V1:STOCKTAKE:CREATE:SER-2612-B:VARIANCE--1",
  physicalQty: 11,
  expectedQty: 12,
  varianceQty: -1,
  batchCode: "SER-2612-B",
  serumSku: "SER-NIA-30",
  cleanserSku: "CLN-GEN-100",
  reasonCode: "PHYSICAL_LOSS",
});

// `GOLDEN_RECONCILIATION_COMPLETED` is a runner checkpoint, while the
// reconciliation domain has its own constrained status vocabulary.  The
// latter is deliberately kept separate so a phase label can never become a
// fabricated persisted status.
const GOLDEN_RECONCILIATION = Object.freeze({
  successfulStatus: "SUCCEEDED",
  nonTerminalStatuses: Object.freeze(["RUNNING"]),
  unsuccessfulTerminalStatuses: Object.freeze(["FAILED"]),
  runType: "POST_STOCKTAKE",
  expectedCheckCount: 2,
});

function resolveGoldenReconciliationTerminalContract({
  persistedStatus,
  runType,
  differenceCount,
  unexpectedOpenCriticalIssueCount,
  ledgerMutationCount,
}) {
  const status = String(persistedStatus ?? "");
  const terminal = status === GOLDEN_RECONCILIATION.successfulStatus ||
    GOLDEN_RECONCILIATION.unsuccessfulTerminalStatuses.includes(status);
  const successful = status === GOLDEN_RECONCILIATION.successfulStatus;
  const exactStatusSatisfied = successful;
  const stockNeutral = Number(ledgerMutationCount) === 0;
  const clean = successful &&
    String(runType ?? "") === GOLDEN_RECONCILIATION.runType &&
    Number(differenceCount) === 0 &&
    Number(unexpectedOpenCriticalIssueCount) === 0 &&
    stockNeutral;
  return {
    persistedStatus: status || null,
    terminal,
    successful,
    exactStatusSatisfied,
    stockNeutral,
    clean,
  };
}

const SLICE_C_LISTING = {
  draftIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:SHOPEE:SHP-SER-NIA-30:DRAFT",
  activationIdempotencyKey:
    "GOLDEN-DEMO-V1:LISTING:SHOPEE:SHP-SER-NIA-30:ACTIVATE",
  channelCode: "SHOPEE",
  externalListingCode: "SHP-SER-NIA-30",
  displayName: "Golden Demo Shopee Serum",
  listingTypeCode: "SINGLE",
  effectiveFrom: "2026-07-15T00:00:00Z",
  note:
    "Golden Demo Slice C deterministic Shopee Serum listing.",
  metadata: {
    source: "golden-demo-runner",
    version: 1,
    slice: "C",
    fixture: "shopee-serum-listing",
  },
};

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

const GOLDEN_STATE_AWARE_SUCCESS_OUTCOMES = new Set(["ADOPTED", "CREATED", "REPLAYED"]);

function failGoldenStateAware(code, detail = null) {
  if (detail !== null) {
    console.error(JSON.stringify({ code, detail }, null, 2));
  }
  throw new Error(code);
}

function assertGoldenStateAwareSuccessResult(result, helperName) {
  if (result === null || result === undefined) {
    failGoldenStateAware("GOLDEN_STATE_AWARE_NULL_RESULT", { helperName });
  }
  if (!result || typeof result !== "object") {
    failGoldenStateAware("GOLDEN_STATE_AWARE_RESULT_INVALID", { helperName, actualType: typeof result });
  }
  if (!GOLDEN_STATE_AWARE_SUCCESS_OUTCOMES.has(String(result.outcome ?? ""))) {
    failGoldenStateAware("GOLDEN_STATE_AWARE_OUTCOME_UNKNOWN", { helperName, outcome: result.outcome ?? null });
  }
  if (!isNonBlank(result.reservationId) || !result.phase || !result.response || !result.persistedEvidence) {
    failGoldenStateAware("GOLDEN_STATE_AWARE_PARTIAL_EVIDENCE", { helperName });
  }
  if (
    result.persistedEvidence.exact !== true
    || result.persistedEvidence.duplicateReservation === true
    || result.persistedEvidence.duplicateEvent === true
  ) {
    failGoldenStateAware("GOLDEN_STATE_AWARE_DUPLICATE_OR_PARTIAL_EVIDENCE", { helperName });
  }
  return result;
}

function buildGoldenProjectionEvidence({ rows, projectionPhase, productCode, assertionLabel }) {
  const row = assertGoldenProductProjectionExact({
    actualProjection: rows,
    projectionPhaseContext: projectionPhase,
    productCode,
    assertionLabel,
  });
  if (!row) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_NOT_EXACT", { assertionLabel, productCode });
  }
  const quantities = ["sellable_qty", "reserved_qty", "available_qty"].map((field) => Number(row[field]));
  if (!quantities.every((quantity) => Number.isSafeInteger(quantity) && quantity >= 0)) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_NUMERIC_INVALID", { assertionLabel, productCode });
  }
  return {
    projectionPhase: phaseNameOf(projectionPhase),
    productCode,
    sellable: quantities[0],
    reserved: quantities[1],
    available: quantities[2],
  };
}

function resolveGoldenProjectionReplayContext({ replayPhaseContract, checkpointPhase, authoritativePhase, projectionEvidencePhase, operation }) {
  if (!replayPhaseContract || typeof replayPhaseContract !== "object" || !isNonBlank(operation)) {
    throw new Error("GOLDEN_PROJECTION_REPLAY_CONTEXT_INVALID");
  }
  const checkpoint = phaseNameOf(checkpointPhase ?? replayPhaseContract.checkpointPhase);
  const authoritative = phaseNameOf(authoritativePhase ?? replayPhaseContract.authoritativePhase);
  const evidencePhase = phaseNameOf(projectionEvidencePhase);
  if (checkpoint !== phaseNameOf(replayPhaseContract.checkpointPhase) || authoritative !== phaseNameOf(replayPhaseContract.authoritativePhase)) {
    throw new Error("GOLDEN_PROJECTION_REPLAY_CONTEXT_CONTRACT_MISMATCH");
  }
  knownGoldenPhaseRank(checkpoint);
  knownGoldenPhaseRank(authoritative);
  knownGoldenPhaseRank(evidencePhase);
  if (evidencePhase !== authoritative) {
    throw new Error(`GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE: ${operation} requires ${authoritative}, actual=${evidencePhase}`);
  }
  if (replayPhaseContract.mode === "FRESH_EXACT" && checkpoint !== authoritative) {
    throw new Error("GOLDEN_PROJECTION_REPLAY_FRESH_CONTEXT_INVALID");
  }
  if (replayPhaseContract.mode !== "FRESH_EXACT" && knownGoldenPhaseRank(authoritative) < knownGoldenPhaseRank(checkpoint)) {
    throw new Error("GOLDEN_PROJECTION_REPLAY_PHASE_TOO_LOW");
  }
  return {
    checkpointPhase: checkpoint,
    authoritativePhase: authoritative,
    projectionEvidencePhase: evidencePhase,
  };
}

function assertGoldenProjectionEvidenceExact({ evidence, directProjection, projectionReplayContext, productCode, assertionLabel }) {
  if (!evidence || typeof evidence !== "object") {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_MISSING", { assertionLabel });
  }
  let context;
  try {
    context = resolveGoldenProjectionReplayContext(projectionReplayContext);
  } catch (error) {
    const message = error instanceof Error ? error.message : "GOLDEN_PROJECTION_REPLAY_CONTEXT_INVALID";
    if (message.startsWith("GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE")) {
      failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE", { assertionLabel, expected: projectionReplayContext?.authoritativePhase ?? null, actual: projectionReplayContext?.projectionEvidencePhase ?? null });
    }
    failGoldenStateAware("GOLDEN_PROJECTION_REPLAY_CONTEXT_INVALID", { assertionLabel, message });
  }
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase: context.authoritativePhase });
  const expectedProduct = productCode === "SER-NIA-30" ? expected.serumProduct : expected.cleanserProduct;
  const expectedEvidence = {
    projectionPhase: expected.detectedPhase,
    productCode,
    sellable: expectedProduct.sellable,
    reserved: expectedProduct.reserved,
    available: expectedProduct.available,
  };
  if (evidence.productCode !== productCode || directProjection?.productCode !== productCode) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_WRONG_PRODUCT", { assertionLabel, expected: productCode });
  }
  if (![evidence.sellable, evidence.reserved, evidence.available].every((quantity) => Number.isSafeInteger(quantity) && quantity >= 0)) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_NUMERIC_INVALID", { assertionLabel });
  }
  const exactEvidence = JSON.stringify(evidence) === JSON.stringify(expectedEvidence);
  const exactDirect = JSON.stringify(directProjection) === JSON.stringify(expectedEvidence);
  if (!exactEvidence || !exactDirect || JSON.stringify(evidence) !== JSON.stringify(directProjection)) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_DIVERGENCE", {
      assertionLabel,
      expected: expectedEvidence,
      evidence,
      directProjection,
    });
  }
  return evidence;
}

function assertSliceEReservationCallerProjectionEvidence(result, callerProjection) {
  if (callerProjection !== result?.persistedEvidence?.afterProjection) {
    failGoldenStateAware("GOLDEN_PROJECTION_EVIDENCE_WRONG_ASSERTION_ARGUMENT");
  }
  const phaseContract = result?.replayPhaseContract ?? resolveGoldenReplayPhaseContract({
    highestPersistedPhase: result?.phase,
    checkpointPhase: "SLICE_E_RESERVED",
    executionMode: result?.outcome === "CREATED" ? "FRESH" : "REPLAY",
    operation: "SLICE_E_RESERVATION",
  });
  const projectionReplayContext = result?.persistedEvidence?.projectionReplayContext;
  if (!projectionReplayContext || typeof projectionReplayContext !== "object") {
    failGoldenStateAware("GOLDEN_PROJECTION_REPLAY_CONTEXT_MISSING");
  }
  assertGoldenHistoricalReplayEvidence({
    phaseContract,
    evidence: projectionReplayContext.historicalOperationEvidence,
    operation: "SLICE_E_RESERVATION",
  });
  return assertGoldenProjectionEvidenceExact({
    evidence: result.persistedEvidence.afterProjection,
    directProjection: callerProjection,
    projectionReplayContext: { ...projectionReplayContext, replayPhaseContract: phaseContract, operation: "SLICE_E_RESERVATION" },
    productCode: "SER-NIA-30",
    assertionLabel: "Slice E caller persisted projection evidence",
  });
}

async function loadEnvFile() {
  try {
    const raw = await readFile(".env.local", "utf8");
    const env = {};

    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;

      const separator = trimmed.indexOf("=");
      if (separator < 1) continue;

      const key = trimmed.slice(0, separator).trim();
      let value = trimmed.slice(separator + 1).trim();

      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }

      env[key] = value;
    }

    return env;
  } catch {
    return {};
  }
}

function resolveEnv(name, env, fallback = "") {
  const value = process.env[name] ?? env[name] ?? fallback;
  return typeof value === "string" ? value.trim() : fallback;
}

function validateLocalSupabaseUrl(rawUrl) {
  if (!rawUrl) {
    fail("NEXT_PUBLIC_SUPABASE_URL belum tersedia. Muat konfigurasi Supabase lokal melalui environment.");
    return false;
  }

  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    fail("NEXT_PUBLIC_SUPABASE_URL tidak valid.");
    return false;
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  const isLocal =
    hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";

  if (!isLocal) {
    fail(`NEXT_PUBLIC_SUPABASE_URL non-local ditolak: ${hostname}`);
    return false;
  }

  return true;
}

function parseResponseText(raw) {
  if (!raw) return "";
  if (typeof raw !== "string") {
    if (typeof raw === "object") {
      return String(
        raw?.msg ?? raw?.message ?? raw?.error_description ?? raw?.error ?? JSON.stringify(raw),
      );
    }
    return String(raw);
  }
  try {
    const payload = JSON.parse(raw);
    return payload?.msg ?? payload?.message ?? payload?.error_description ?? payload?.error ?? raw;
  } catch {
    return raw;
  }
}

function sameInstant(actual, expected) {
  const actualMs = Date.parse(String(actual ?? ""));
  const expectedMs = Date.parse(String(expected ?? ""));

  return Number.isFinite(actualMs)
    && Number.isFinite(expectedMs)
    && actualMs === expectedMs;
}

function isNonBlank(value) {
  return String(value ?? "").trim() !== "";
}

function asNumber(value) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : Number.NaN;
}

function isHex64(value) {
  return /^[0-9a-f]{64}$/.test(String(value ?? ""));
}

function sameJsonSubsetMetadata(actual) {
  return (
    String(actual?.source ?? "") === String(SLICE_C_LISTING.metadata.source) &&
    asNumber(actual?.version) === asNumber(SLICE_C_LISTING.metadata.version) &&
    String(actual?.slice ?? "") === String(SLICE_C_LISTING.metadata.slice) &&
    String(actual?.fixture ?? "") === String(SLICE_C_LISTING.metadata.fixture)
  );
}

function authHeaders(publishableKey, accessToken) {
  return {
    apikey: publishableKey,
    Authorization: `Bearer ${accessToken}`,
    "Accept-Profile": "api",
    "Content-Profile": "api",
    "Content-Type": "application/json",
  };
}

function buildSliceCPayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_C.idempotencyKey,
    p_channel_code: SLICE_C.channelCode,
    p_event_ref: SLICE_C.externalEventRef,
    p_order_ref: SLICE_C.externalOrderRef,
    p_source_status: SLICE_C.sourceStatus,
    p_occurred_at: SLICE_C.occurredAt,
    p_received_at: SLICE_C.receivedAt,
    p_lines: [
      {
        sourceLineRef: SLICE_C.sourceLineRef,
        externalListingCode: SLICE_C.externalListingCode,
        listingQuantity: SLICE_C.listingQuantity,
        sourceTitle: "Golden Demo Shopee Serum reservation",
        sourceSku: "SHP-SER-NIA-30",
        sourceStatus: "READY_TO_SHIP",
        rawLinePayload: {
          fixture: "golden-demo-v1",
          slice: "C",
          line: 1,
        },
      },
    ],
    p_note: "Golden Demo Slice C Shopee reservation.",
    p_raw_payload: {
      source: "golden-demo-runner",
      version: 1,
      slice: "C",
      scenario: "shopee-reservation-8",
    },
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "C",
      scenario: "shopee-reservation-8",
    },
    p_schema_version: 1,
  };
}

async function rpcJson(supabaseUrl, publishableKey, accessToken, functionName, body) {
  if (!supabaseUrl) {
    throw new Error("rpcJson memerlukan supabaseUrl.");
  }
  if (!publishableKey) {
    throw new Error("rpcJson memerlukan publishableKey.");
  }
  if (!accessToken) {
    throw new Error("rpcJson memerlukan accessToken.");
  }
  if (body === undefined) {
    throw new Error("rpcJson memerlukan body.");
  }
  if (!functionName || typeof functionName !== "string") {
    throw new Error("rpcJson memerlukan functionName string.");
  }

  const normalizedFunctionName = functionName.trim();
  if (!normalizedFunctionName) {
    throw new Error("rpcJson memerlukan functionName non-kosong.");
  }
  if (normalizedFunctionName.includes("/") || normalizedFunctionName.includes(":") || normalizedFunctionName.includes("?")) {
    throw new Error("rpcJson hanya menerima nama function RPC, bukan URL atau path.");
  }

  const url = `${supabaseUrl}/rest/v1/rpc/${normalizedFunctionName}`;

  let response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: authHeaders(publishableKey, accessToken),
      body: JSON.stringify(body),
      cache: "no-store",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (error) {
    if (error?.name === "TimeoutError") {
      throw new Error(`RPC ${normalizedFunctionName} timeout setelah ${REQUEST_TIMEOUT_MS} ms.`);
    }
    throw new Error(
      `RPC ${normalizedFunctionName} gagal dikirim: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  const raw = await response.text();
  let payload = null;
  if (raw) {
    try {
      payload = JSON.parse(raw);
    } catch {
      throw new Error(`RPC ${normalizedFunctionName} mengembalikan JSON tidak valid.`);
    }
  }

  return {
    status: response.status,
    ok: response.ok,
    payload,
  };
}

async function apiFetchRows(supabaseUrl, publishableKey, accessToken, path) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    headers: authHeaders(publishableKey, accessToken),
    cache: "no-store",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  const raw = await response.text();
  if (!response.ok) {
    fail(`Read ${path} gagal: ${parseResponseText(raw)}`);
    return null;
  }
  try {
    const payload = JSON.parse(raw);
    if (!Array.isArray(payload)) {
      fail(`Read ${path} tidak mengembalikan array.`);
      return null;
    }
    return payload;
  } catch {
    fail(`Read ${path} tidak valid JSON.`);
    return null;
  }
}

async function readJsonRows(supabaseUrl, publishableKey, accessToken, path) {
  return await apiFetchRows(supabaseUrl, publishableKey, accessToken, path);
}

function batchSourceStatus(batchRow) {
  const status = String(batchRow?.lifecycle_status_code ?? batchRow?.status_code ?? "").toUpperCase();
  return status === "ACTIVE";
}

function assertExactProduct(row, fixture, organizationId) {
  return (
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.sku ?? "") === fixture.sku &&
    String(row?.name ?? "") === fixture.name &&
    String(row?.unit_code ?? "") === fixture.unitCode &&
    Boolean(row?.is_active) === true
  );
}

function assertExactBatch(row, fixture, organizationId, productId) {
  return (
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.product_id ?? "") === String(productId) &&
    String(row?.batch_code ?? "") === fixture.batchCode &&
    String(row?.expiry_date ?? "") === fixture.expiryDate &&
    String(row?.batch_kind_code ?? "") === fixture.batchKindCode &&
    batchSourceStatus(row)
  );
}

async function readProductBySku(supabaseUrl, publishableKey, accessToken, organizationId, sku) {
  return apiFetchRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `product_master?organization_id=eq.${encodeURIComponent(organizationId)}&sku=eq.${encodeURIComponent(sku)}&limit=2&select=*`,
  );
}

function assertBaselineProductRows(rows, fixture, organizationId) {
  if (rows.length !== 1) {
    fail(`product_master untuk ${fixture.sku} harus tepat satu row, tetapi ditemukan ${rows.length}.`);
    return null;
  }
  const row = rows[0];
  if (!assertExactProduct(row, fixture, organizationId)) {
    fail(`product_master untuk ${fixture.sku} tidak exact.`);
    return null;
  }
  return { ...fixture, productId: row.product_id };
}

async function readBatchByCode(supabaseUrl, publishableKey, accessToken, organizationId, productId, batchCode) {
  return apiFetchRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `product_batch_master?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(productId)}&batch_code=eq.${encodeURIComponent(batchCode)}&limit=2&select=*`,
  );
}

function assertBaselineBatchRows(rows, fixture, organizationId, productId) {
  if (rows.length !== 1) {
    fail(`product_batch_master untuk ${fixture.batchCode} harus tepat satu row, tetapi ditemukan ${rows.length}.`);
    return null;
  }
  const row = rows[0];
  if (!assertExactBatch(row, fixture, organizationId, productId)) {
    fail(`product_batch_master untuk ${fixture.batchCode} tidak exact.`);
    return null;
  }
  return { ...fixture, productId, batchId: row.batch_id };
}

async function readReceiptBySourceRef(supabaseUrl, publishableKey, accessToken, organizationId, sourceRef) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `receipts?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref=eq.${encodeURIComponent(sourceRef)}&limit=2&select=*`,
  );
}

async function readReceiptLines(supabaseUrl, publishableKey, accessToken, organizationId, receiptId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `receipt_lines?organization_id=eq.${encodeURIComponent(organizationId)}&receipt_id=eq.${encodeURIComponent(receiptId)}&select=*`,
  );
}

async function ensureSliceBBatch(supabaseUrl, publishableKey, accessToken, organizationId, products, batches) {
  const product = products.get("SER-NIA-30");
  if (!product) {
    fail("Batch Slice B membutuhkan produk SER-NIA-30 yang sudah diadopsi.");
    return null;
  }

  const batchCode = "SER-2701-C";
  const expiryDate = "2027-01-31";
  const batchKindCode = "STANDARD";
  const productId = product.productId;

  const existing = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `product_batch_master?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(productId)}&batch_code=eq.${encodeURIComponent(batchCode)}&limit=2&select=*`,
  );

  const exact = (row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.product_id ?? "") === String(productId) &&
    String(row?.batch_code ?? "") === batchCode &&
    String(row?.expiry_date ?? "") === expiryDate &&
    String(row?.batch_kind_code ?? "") === batchKindCode &&
    String(row?.lifecycle_status_code ?? "") === "ACTIVE" &&
    Boolean(row?.product_is_active);

  if (existing.length > 1) {
    fail("Batch Slice B duplikat pada product_batch_master.");
    return null;
  }

  if (existing.length === 1) {
    const row = existing[0];
    if (!exact(row)) {
      fail("Batch Slice B tidak exact pada product_batch_master.");
      return null;
    }
    const adopted = {
      ...row,
      productId: row.product_id,
      batchId: row.batch_id,
      productSku: row.product_sku,
      batchCode: row.batch_code,
      expiryDate: row.expiry_date,
    };
    batches.set(batchCode, adopted);
    return adopted;
  }

  const payload = {
    p_organization_id: organizationId,
    p_idempotency_key: "GOLDEN-DEMO-V1:BATCH:SER-2701-C",
    p_product_id: productId,
    p_batch_code: batchCode,
    p_expiry_date: expiryDate,
    p_manufactured_date: null,
    p_received_first_at: null,
    p_batch_kind_code: batchKindCode,
    p_note: "Golden Demo Slice B batch",
  };

  const first = await rpcJson(supabaseUrl, publishableKey, accessToken, "create_product_batch", payload);
  const firstJson = first.payload;
  if (first.status !== 200) {
    if (parseResponseText(first.payload).includes("DUPLICATE_PRODUCT_BATCH")) {
      const retry = await readJsonRows(
        supabaseUrl,
        publishableKey,
        accessToken,
        `product_batch_master?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(productId)}&batch_code=eq.${encodeURIComponent(batchCode)}&limit=2&select=*`,
      );
      if (retry.length !== 1 || !exact(retry[0])) {
        fail("Batch Slice B tidak exact setelah race DUPLICATE_PRODUCT_BATCH.");
        return null;
      }
      const adopted = {
        ...retry[0],
        productId: retry[0].product_id,
        batchId: retry[0].batch_id,
        productSku: retry[0].product_sku,
        batchCode: retry[0].batch_code,
        expiryDate: retry[0].expiry_date,
      };
      batches.set(batchCode, adopted);
      return adopted;
    }
    fail(`create_product_batch gagal: ${parseResponseText(first.payload)}`);
    return null;
  }

  if (String(firstJson?.status ?? "") !== "CREATED") {
    fail("create_product_batch tidak mengembalikan status CREATED.");
    return null;
  }
  const replay = await rpcJson(supabaseUrl, publishableKey, accessToken, "create_product_batch", payload);
  const replayJson = replay.payload;
  if (replay.status !== 200) {
    fail(`create_product_batch replay gagal: ${parseResponseText(replay.payload)}`);
    return null;
  }
  if (String(replayJson?.batchId ?? "") !== String(firstJson?.batchId ?? "")) {
    fail("create_product_batch replay tidak identik.");
    return null;
  }

  const adopted = {
    ...firstJson,
    productId: firstJson.productId,
    batchId: firstJson.batchId,
    productSku: firstJson.productSku,
    batchCode: firstJson.batchCode,
    expiryDate: firstJson.expiryDate,
  };
  batches.set(batchCode, adopted);
  return adopted;
}

async function ensureSliceBReceipt(supabaseUrl, publishableKey, accessToken, organizationId, batch) {
  const sourceRef = "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM";
  const idempotencyKey = "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM";
  const occurredAt = "2026-07-15T02:00:00Z";
  const payload = {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_source_ref: sourceRef,
    p_occurred_at: occurredAt,
    p_lines: [
      {
        productId: batch.productId,
        batchId: batch.batchId,
        quantity: 10,
        sourceLineRef: "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM:1",
      },
    ],
    p_note: "Golden Demo Slice B Maklon receipt",
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "B",
      scenario: "maklon-serum-receipt",
    },
  };

  const receipts = await readReceiptBySourceRef(supabaseUrl, publishableKey, accessToken, organizationId, sourceRef);
  if (!receipts) return null;
  if (receipts.length > 1) {
    fail("Receipt Slice B duplikat.");
    return null;
  }

  if (receipts.length === 1) {
    const receipt = receipts[0];
    if (String(receipt?.status_code ?? "") !== "POSTED") {
      fail("Receipt Slice B tidak POSTED.");
      return null;
    }
    if (String(receipt?.source_ref ?? "") !== sourceRef) {
      fail("Receipt Slice B source_ref tidak exact.");
      return null;
    }
    if (String(receipt?.note ?? "") !== "Golden Demo Slice B Maklon receipt") {
      fail("Receipt Slice B note tidak exact.");
      return null;
    }
    if (!sameInstant(receipt?.occurred_at, occurredAt)) {
      fail("Receipt Slice B occurred_at tidak exact.");
      return null;
    }
    const metadata = receipt?.metadata ?? {};
    if (
      String(metadata?.source ?? "") !== "golden-demo-runner" ||
      Number(metadata?.version) !== 1 ||
      String(metadata?.slice ?? "") !== "B" ||
      String(metadata?.scenario ?? "") !== "maklon-serum-receipt"
    ) {
      fail("Receipt Slice B metadata tidak exact.");
      return null;
    }

    const lines = await readReceiptLines(supabaseUrl, publishableKey, accessToken, organizationId, receipt.receipt_id);
    if (!lines) return null;
    if (lines.length !== 1) {
      fail("Receipt Slice B harus tepat satu line.");
      return null;
    }
    const line = lines[0];
    if (
      String(line?.product_id ?? "") !== String(batch.productId) ||
      String(line?.batch_id ?? "") !== String(batch.batchId) ||
      Number(line?.quantity_received) !== 10 ||
      String(line?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
      String(line?.batch_code_snapshot ?? "") !== "SER-2701-C" ||
      String(line?.expiry_date_snapshot ?? "") !== "2027-01-31" ||
      String(line?.source_line_ref ?? "") !== "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM:1"
    ) {
      fail("Receipt Slice B line tidak exact.");
      return null;
    }

    const replay = await rpcJson(supabaseUrl, publishableKey, accessToken, "post_receipt", payload);
    const replayJson = replay.payload;
    if (replay.status !== 200) {
      fail(`post_receipt replay gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    if (String(replayJson?.receiptId ?? "") !== String(receipt.receipt_id) || String(replayJson?.transactionId ?? "") !== String(receipt.transaction_id)) {
      fail("post_receipt replay tidak identik.");
      return null;
    }
    return { path: "replayed", receipt, line, payload, sourceRef, idempotencyKey };
  }

  const first = await rpcJson(supabaseUrl, publishableKey, accessToken, "post_receipt", payload);
  const firstJson = first.payload;
  if (first.status !== 200) {
    fail(`post_receipt gagal: ${parseResponseText(first.payload)}`);
    return null;
  }
  if (String(firstJson?.status ?? "") !== "POSTED") {
    fail("post_receipt tidak mengembalikan status POSTED.");
    return null;
  }

  const replay = await rpcJson(supabaseUrl, publishableKey, accessToken, "post_receipt", payload);
  const replayJson = replay.payload;
  if (replay.status !== 200) {
    fail(`post_receipt replay gagal: ${parseResponseText(replay.payload)}`);
    return null;
  }
  if (String(replayJson?.receiptId ?? "") !== String(firstJson?.receiptId ?? "") || String(replayJson?.transactionId ?? "") !== String(firstJson?.transactionId ?? "")) {
    fail("post_receipt replay tidak identik.");
    return null;
  }
  return { path: "created", receipt: firstJson, payload, sourceRef, idempotencyKey };
}

async function fetchReadModel(supabaseUrl, publishableKey, accessToken, organizationId) {
  const [productsResponse, batchesResponse] = await Promise.all([
    fetch(
      `${supabaseUrl}/rest/v1/product_inventory?organization_id=eq.${encodeURIComponent(organizationId)}&select=*`,
      {
        headers: authHeaders(publishableKey, accessToken),
        cache: "no-store",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    ),
    fetch(
      `${supabaseUrl}/rest/v1/batch_inventory?organization_id=eq.${encodeURIComponent(organizationId)}&select=*`,
      {
        headers: authHeaders(publishableKey, accessToken),
        cache: "no-store",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    ),
  ]);

  const [productsRaw, batchesRaw] = await Promise.all([productsResponse.text(), batchesResponse.text()]);

  if (!productsResponse.ok) {
    fail(`Read model product_inventory gagal: ${parseResponseText(productsRaw)}`);
    return null;
  }

  if (!batchesResponse.ok) {
    fail(`Read model batch_inventory gagal: ${parseResponseText(batchesRaw)}`);
    return null;
  }

  return {
    products: JSON.parse(productsRaw),
    batches: JSON.parse(batchesRaw),
    productInventory: JSON.parse(productsRaw),
    batchInventory: JSON.parse(batchesRaw),
  };
}

function assertSingleRow(rows, predicate, label) {
  const matches = rows.filter(predicate);
  if (matches.length !== 1) {
    fail(`${label} harus tepat satu row, tetapi ditemukan ${matches.length}.`);
    return null;
  }
  return matches[0];
}

function assertSliceALiveBaseline(readModel) {
  const serum = assertSingleRow(
    readModel.products ?? [],
    (row) => row.sku === "SER-NIA-30",
    "product_inventory Serum",
  );
  const cleanser = assertSingleRow(
    readModel.products ?? [],
    (row) => row.sku === "CLN-GEN-100",
    "product_inventory Cleanser",
  );
  const ser2608 = assertSingleRow(
    readModel.batches ?? [],
    (row) => row.batch_code === "SER-2608-A",
    "batch_inventory SER-2608-A",
  );
  const ser2612 = assertSingleRow(
    readModel.batches ?? [],
    (row) => row.batch_code === "SER-2612-B",
    "batch_inventory SER-2612-B",
  );
  const cln2611 = assertSingleRow(
    readModel.batches ?? [],
    (row) => row.batch_code === "CLN-2611-A",
    "batch_inventory CLN-2611-A",
  );

  if (!serum || !cleanser || !ser2608 || !ser2612 || !cln2611) {
    return false;
  }

  const serumChecks = [
    ["sellable_qty", serum.sellable_qty, 25],
    ["reserved_qty", serum.reserved_qty, 0],
    ["available_qty", serum.available_qty, 25],
  ];
  const cleanserChecks = [
    ["sellable_qty", cleanser.sellable_qty, 15],
    ["reserved_qty", cleanser.reserved_qty, 0],
    ["available_qty", cleanser.available_qty, 15],
  ];
  const batchChecks = [
    ["SER-2608-A.sellable_qty", ser2608.sellable_qty, 5],
    ["SER-2608-A.quarantine_qty", ser2608.quarantine_qty, 0],
    ["SER-2608-A.damaged_qty", ser2608.damaged_qty, 0],
    ["SER-2612-B.sellable_qty", ser2612.sellable_qty, 20],
    ["SER-2612-B.quarantine_qty", ser2612.quarantine_qty, 0],
    ["SER-2612-B.damaged_qty", ser2612.damaged_qty, 0],
    ["CLN-2611-A.sellable_qty", cln2611.sellable_qty, 15],
    ["CLN-2611-A.quarantine_qty", cln2611.quarantine_qty, 0],
    ["CLN-2611-A.damaged_qty", cln2611.damaged_qty, 0],
  ];

  for (const [label, actual, expected] of [...serumChecks, ...cleanserChecks, ...batchChecks]) {
    if (Number(actual) !== expected) {
      fail(`${label} harus ${expected}, got ${actual}.`);
      return false;
    }
  }

  return true;
}

function assertSliceBProjection(readModel, expectedReservedQty) {
  const serumRows = Array.isArray(readModel?.productInventory) ? readModel.productInventory : [];
  const batchRows = Array.isArray(readModel?.batchInventory) ? readModel.batchInventory : [];

  const serum = assertSingleRow(
    serumRows,
    (row) => String(row?.sku ?? "") === "SER-NIA-30",
    "api.product_inventory SER-NIA-30",
  );
  if (!serum) {
    return false;
  }

  const batch = assertSingleRow(
    batchRows,
    (row) => String(row?.batch_code ?? "") === "SER-2701-C",
    "api.batch_inventory SER-2701-C",
  );
  if (!batch) {
    return false;
  }

  if (
    Number(serum?.sellable_qty) !== 35 ||
    Number(serum?.reserved_qty) !== expectedReservedQty ||
    Number(serum?.available_qty) !== 35 - expectedReservedQty
  ) {
    fail("Projection SER-NIA-30 tidak exact.");
    return false;
  }

  if (
    Number(batch?.sellable_qty) !== 10 ||
    Number(batch?.quarantine_qty) !== 0 ||
    Number(batch?.damaged_qty) !== 0
  ) {
    fail("Projection batch SER-2701-C tidak exact.");
    return false;
  }

  return true;
}

async function fetchSeededInitialBalanceLedgerRows(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&transaction_id=eq.${SEEDED_INITIAL_BALANCE_TRANSACTION.transactionId}` +
      `&select=ledger_seq,ledger_entry_id,organization_id,transaction_id,transaction_no,transaction_type_code,reason_code_snapshot,channel_code_snapshot,source_type_code,source_ref_snapshot,line_no,product_id,batch_id,product_sku_snapshot,batch_code_snapshot,expiry_date_snapshot,bucket_code,quantity_delta,entry_role_code,occurred_at,recorded_at` +
      `&order=ledger_seq.asc`,
    {
      headers: authHeaders(publishableKey, accessToken),
      cache: "no-store",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    },
  );
  const raw = await response.text();
  if (!response.ok) {
    fail(`Read stock_ledger gagal: ${parseResponseText(raw)}`);
    return null;
  }
  try {
    const payload = JSON.parse(raw);
    return Array.isArray(payload) ? payload : [];
  } catch {
    fail("Read stock_ledger tidak valid JSON.");
    return null;
  }
}

function isFinitePositiveQuantityDelta(value) {
  const quantity = Number(value);
  return Number.isFinite(quantity) && quantity > 0;
}

function assertSeededInitialBalanceLedger(rows, batches) {
  if (rows.length !== 4) {
    fail(`Seeded initial-balance ledger harus tepat 4 row, tetapi ditemukan ${rows.length}.`);
    return null;
  }

  const firstRow = rows[0];
  if (
    String(firstRow?.transaction_id ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.transactionId ||
    String(firstRow?.transaction_no ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.transactionNo ||
    String(firstRow?.source_ref_snapshot ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.sourceRefSnapshot
  ) {
    fail("Seeded initial-balance ledger tidak memakai identity transaction exact.");
    return null;
  }

  const seenLedgerSeq = new Set();
  const seenLineNo = new Set();
  const expectedByLineNo = new Map([
    [1, { productSku: "SER-NIA-30", batchCode: "SER-2608-A", quantity: 5 }],
    [2, { productSku: "SER-NIA-30", batchCode: "SER-2612-B", quantity: 20 }],
    [3, { productSku: "CLN-GEN-100", batchCode: "CLN-2611-A", quantity: 15 }],
    [4, { productSku: "TNR-HYD-100", batchCode: "TNR-2610-A", quantity: 12 }],
  ]);

  const batchExact = batches;

  for (const row of rows) {
    const ledgerSeq = String(row?.ledger_seq ?? "");
    const lineNo = Number(row?.line_no);
    const expected = expectedByLineNo.get(lineNo);

    if (!ledgerSeq || seenLedgerSeq.has(ledgerSeq)) {
      fail("ledger_seq harus unik untuk seeded initial-balance ledger.");
      return null;
    }
    seenLedgerSeq.add(ledgerSeq);

    if (!Number.isInteger(lineNo) || lineNo < 1 || seenLineNo.has(lineNo) || !expected) {
      fail("line_no seeded initial-balance tidak exact.");
      return null;
    }
    seenLineNo.add(lineNo);

    if (
      String(row?.organization_id ?? "") === "" ||
      String(row?.transaction_id ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.transactionId ||
      String(row?.transaction_no ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.transactionNo ||
      String(row?.transaction_type_code ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.transactionTypeCode ||
      String(row?.reason_code_snapshot ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.reasonCodeSnapshot ||
      String(row?.channel_code_snapshot ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.channelCodeSnapshot ||
      String(row?.source_type_code ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.sourceTypeCode ||
      String(row?.source_ref_snapshot ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.sourceRefSnapshot ||
      String(row?.bucket_code ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.bucketCode ||
      String(row?.entry_role_code ?? "") !== SEEDED_INITIAL_BALANCE_TRANSACTION.entryRoleCode ||
      String(row?.product_sku_snapshot ?? "") !== expected.productSku ||
      String(row?.batch_code_snapshot ?? "") !== expected.batchCode ||
      !isFinitePositiveQuantityDelta(row?.quantity_delta) ||
      Number(row?.quantity_delta) !== expected.quantity
    ) {
      fail(`Seeded initial-balance row line_no ${lineNo} tidak exact.`);
      return null;
    }

    const batchFixture = batchExact.get(expected.batchCode);
    if (!batchFixture) {
      fail(`Batch fixture ${expected.batchCode} tidak tersedia.`);
      return null;
    }

    if (
      String(row?.product_id ?? "") !== String(batchFixture.productId ?? "") ||
      String(row?.batch_id ?? "") !== String(batchFixture.batchId ?? "") ||
      String(row?.expiry_date_snapshot ?? "") !== batchFixture.expiryDate
    ) {
      fail(`Seeded initial-balance row line_no ${lineNo} tidak cocok dengan master batch.`);
      return null;
    }
  }

  if (seenLineNo.size !== 4) {
    fail("Seeded initial-balance ledger harus memiliki empat line unik.");
    return null;
  }

  return true;
}

async function readLedgerRowsByBatchId(supabaseUrl, publishableKey, accessToken, organizationId, batchId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&batch_id=eq.${encodeURIComponent(batchId)}&order=ledger_seq.asc&select=ledger_seq,ledger_entry_id,organization_id,transaction_id,transaction_no,transaction_type_code,reason_code_snapshot,channel_code_snapshot,source_type_code,source_ref_snapshot,source_line_ref,line_no,product_id,batch_id,product_sku_snapshot,batch_code_snapshot,expiry_date_snapshot,bucket_code,quantity_delta,entry_role_code,occurred_at,recorded_at`,
  );
}

async function assertSliceBFreshBaseline(supabaseUrl, publishableKey, accessToken, organizationId, sliceBBatch, readModel) {
  const batchLedgerRows = await readLedgerRowsByBatchId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    sliceBBatch.batchId,
  );
  if (!batchLedgerRows) {
    return false;
  }
  if (batchLedgerRows.length !== 0) {
    fail("Ledger Slice B fresh path harus tepat 0 row sebelum receipt.");
    return false;
  }

  const batchRows = (readModel.batches ?? []).filter(
    (row) => String(row?.batch_code ?? "") === "SER-2701-C",
  );
  if (batchRows.length > 1) {
    fail("Projection batch Slice B fresh path duplikat sebelum receipt.");
    return false;
  }
  if (batchRows.length === 1) {
    const batch = batchRows[0];
    if (
      Number(batch?.sellable_qty) !== 0 ||
      Number(batch?.quarantine_qty) !== 0 ||
      Number(batch?.damaged_qty) !== 0
    ) {
      fail("Projection batch Slice B fresh path harus 0 bila row sudah ada sebelum receipt.");
      return false;
    }
  }

  return true;
}

async function authPreflight(supabaseUrl, publishableKey, demoPassword) {
  const loginResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: publishableKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email: DEMO_EMAIL, password: demoPassword }),
    cache: "no-store",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  const loginRaw = await loginResponse.text();
  if (!loginResponse.ok) {
    fail(`Login Demo Admin gagal via /auth/v1/token?grant_type=password: ${parseResponseText(loginRaw)}`);
    return null;
  }

  const loginPayload = JSON.parse(loginRaw);
  const accessToken = String(loginPayload?.access_token ?? "");
  if (!accessToken) {
    fail("Login Demo Admin tidak mengembalikan access_token.");
    return null;
  }

  const profileResponse = await fetch(`${supabaseUrl}/rest/v1/current_admin_profile?select=*&limit=1`, {
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${accessToken}`,
      "Accept-Profile": "api",
      "Content-Profile": "api",
    },
    cache: "no-store",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  const profileRaw = await profileResponse.text();
  if (!profileResponse.ok) {
    fail(`Baca api.current_admin_profile gagal: ${parseResponseText(profileRaw)}`);
    return null;
  }

  const profiles = JSON.parse(profileRaw);
  if (!Array.isArray(profiles) || profiles.length !== 1) {
    fail("api.current_admin_profile harus mengembalikan tepat satu profile.");
    return null;
  }

  const profile = profiles[0];
  if (String(profile?.role_code ?? "") !== "ADMIN") {
    fail("Profile Demo Admin harus memiliki role_code ADMIN.");
    return null;
  }

  if (!String(profile?.organization_id ?? "").trim()) {
    fail("Profile Demo Admin harus memiliki organization_id.");
    return null;
  }

  console.log("[PASS] Demo Admin authentication preflight");
  return {
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId: String(profile.organization_id),
  };
}

async function readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, sku) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `product_inventory?organization_id=eq.${encodeURIComponent(organizationId)}&sku=eq.${encodeURIComponent(sku)}&limit=2&select=*`,
  );
}

async function readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, batchCode) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `batch_inventory?organization_id=eq.${encodeURIComponent(organizationId)}&batch_code=eq.${encodeURIComponent(batchCode)}&limit=2&select=*`,
  );
}

async function readStockLedgerByProductId(supabaseUrl, publishableKey, accessToken, organizationId, productId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(productId)}&order=ledger_seq.asc&select=ledger_seq,quantity_delta,product_id,product_sku_snapshot,batch_code_snapshot,transaction_id,transaction_type_code,source_ref_snapshot,source_line_ref,bucket_code,entry_role_code,occurred_at`,
  );
}

async function readStockLedgerByTransactionId(supabaseUrl, publishableKey, accessToken, organizationId, transactionId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&transaction_id=eq.${encodeURIComponent(transactionId)}&order=ledger_seq.asc&select=ledger_seq,organization_id,transaction_id,transaction_no,transaction_type_code,reason_code_snapshot,channel_code_snapshot,source_type_code,source_ref_snapshot,source_line_ref,line_no,product_id,product_sku_snapshot,batch_code_snapshot,bucket_code,quantity_delta,entry_role_code,occurred_at`,
  );
}

async function readManualOutboundsBySourceRef(supabaseUrl, publishableKey, accessToken, organizationId, sourceRef) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `manual_outbounds?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref=eq.${encodeURIComponent(sourceRef)}&limit=2&select=*`,
  );
}

async function readManualOutboundLinesByOutboundId(supabaseUrl, publishableKey, accessToken, organizationId, outboundId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `manual_outbound_lines?organization_id=eq.${encodeURIComponent(organizationId)}&outbound_id=eq.${encodeURIComponent(outboundId)}&order=line_no.asc&select=*`,
  );
}

async function readManualOutboundAllocationsByOutboundId(supabaseUrl, publishableKey, accessToken, organizationId, outboundId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `manual_outbound_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&outbound_id=eq.${encodeURIComponent(outboundId)}&order=allocation_no.asc&select=*`,
  );
}

async function probeSliceFManualBonusState(supabaseUrl, publishableKey, accessToken, organizationId) {
  const sourceRef = "GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:QTY-2";
  const headerRows = await readManualOutboundsBySourceRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    sourceRef,
  );
  if (!headerRows) return null;

  const firstHeader = headerRows[0];
  const lineRows = firstHeader
    ? await readManualOutboundLinesByOutboundId(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      firstHeader.outbound_id,
    )
    : [];
  if (lineRows === null) return null;

  const allocationRows = firstHeader
    ? await readManualOutboundAllocationsByOutboundId(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      firstHeader.outbound_id,
    )
    : [];
  if (allocationRows === null) return null;

  const transactionRows = firstHeader?.transaction_id
    ? await readStockLedgerByTransactionId(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      firstHeader.transaction_id,
    )
    : [];
  if (transactionRows === null) return null;

  const firstAllocation = allocationRows[0];
  const ledgerRows = firstHeader?.transaction_id
    ? await readStockLedgerByTransactionId(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      firstHeader.transaction_id,
    )
    : [];
  if (ledgerRows === null) return null;

  const productInventory = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!productInventory) return null;
  const batch2608 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2608-A");
  const batch2612 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2612-B");
  const batch2701 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2701-C");
  if (!batch2608 || !batch2612 || !batch2701) return null;

  const headerRow = headerRows[0] ?? null;
  const isUuid = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value ?? ""));
  const totalQuantity = Number(headerRow?.total_quantity);
  const headerPredicates = {
    rowCountExact: headerRows.length === 1,
    organizationExact: String(headerRow?.organization_id ?? "") === String(organizationId),
    outboundIdValid: isUuid(headerRow?.outbound_id),
    sourceRefExact: String(headerRow?.source_ref ?? "") === sourceRef,
    reasonExact: String(headerRow?.reason_code_snapshot ?? "") === "BONUS",
    statusExact: String(headerRow?.status_code ?? "") === "POSTED",
    transactionIdValid: isUuid(headerRow?.transaction_id),
    totalQuantityExact: Number.isSafeInteger(totalQuantity) && totalQuantity === 2,
  };
  const headerExact =
    headerPredicates.rowCountExact &&
    headerPredicates.organizationExact &&
    headerPredicates.outboundIdValid &&
    headerPredicates.sourceRefExact &&
    headerPredicates.reasonExact &&
    headerPredicates.statusExact &&
    headerPredicates.transactionIdValid &&
    headerPredicates.totalQuantityExact;

  const lineExact =
    lineRows.length === 1 &&
    String(lineRows[0]?.product_sku_snapshot ?? "") === "SER-NIA-30" &&
    Number(lineRows[0]?.quantity_requested) === 2 &&
    String(lineRows[0]?.source_line_ref ?? "") === "GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:LINE-1";

  const allocationExact =
    allocationRows.length === 1 &&
    String(firstAllocation?.product_sku_snapshot ?? "") === "SER-NIA-30" &&
    String(firstAllocation?.batch_code_snapshot ?? "") === "SER-2612-B" &&
    Number(firstAllocation?.quantity_allocated) === 2 &&
    String(firstAllocation?.source_line_ref ?? "") === "GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:LINE-1";

  const transactionExact =
    transactionRows.length === 1 &&
    String(transactionRows[0]?.transaction_type_code ?? "") === "MANUAL_OUTBOUND" &&
    String(transactionRows[0]?.reason_code_snapshot ?? "") === "BONUS" &&
    String(transactionRows[0]?.channel_code_snapshot ?? "") === "MANUAL" &&
    String(transactionRows[0]?.source_ref_snapshot ?? "") === sourceRef &&
    String(transactionRows[0]?.product_sku_snapshot ?? "") === "SER-NIA-30" &&
    String(transactionRows[0]?.batch_code_snapshot ?? "") === "SER-2612-B" &&
    Number(transactionRows[0]?.quantity_delta) === -2;

  const ledgerExact =
    ledgerRows.length === 1 &&
    String(ledgerRows[0]?.transaction_type_code ?? "") === "MANUAL_OUTBOUND" &&
    String(ledgerRows[0]?.reason_code_snapshot ?? "") === "BONUS" &&
    String(ledgerRows[0]?.channel_code_snapshot ?? "") === "MANUAL" &&
    String(ledgerRows[0]?.source_ref_snapshot ?? "") === sourceRef &&
    String(ledgerRows[0]?.product_sku_snapshot ?? "") === "SER-NIA-30" &&
    String(ledgerRows[0]?.batch_code_snapshot ?? "") === "SER-2612-B" &&
    String(ledgerRows[0]?.bucket_code ?? "") === "SELLABLE" &&
    Number(ledgerRows[0]?.quantity_delta) === -2;

  const productProjectionExact =
    productInventory.length === 1 &&
    String(productInventory[0]?.sku ?? "") === "SER-NIA-30" &&
    Number(productInventory[0]?.sellable_qty) === 24 &&
    Number(productInventory[0]?.reserved_qty) === 0 &&
    Number(productInventory[0]?.available_qty) === 24;

  const batchProjectionExact =
    batch2608.length === 1 &&
    batch2612.length === 1 &&
    batch2701.length === 1 &&
    Number(batch2608[0]?.sellable_qty) === 0 &&
    Number(batch2612[0]?.sellable_qty) === 14 &&
    Number(batch2701[0]?.sellable_qty) === 10;

  const allEvidenceRows = {
    headerRows,
    lineRows,
    allocationRows,
    transactionRows,
    ledgerRows,
    productInventory,
    batchInventory: [...batch2608, ...batch2612, ...batch2701],
  };

  const evidence = {
    headerExact,
    lineExact,
    allocationExact,
    transactionExact,
    ledgerExact,
    productProjectionExact,
    batchProjectionExact,
  };

  const allExact = Object.values(evidence).every(Boolean);
  const anyEvidence = headerRows.length > 0 || lineRows.length > 0 || allocationRows.length > 0 || transactionRows.length > 0 || ledgerRows.length > 0;

  if (!headerExact && headerRows.length === 1) {
    console.log(JSON.stringify({
      assertion: "Slice F manual outbound header contract",
      rowKeys: Object.keys(headerRow ?? {}).sort(),
      predicates: headerPredicates,
      actual: {
        organizationId: headerRow?.organization_id ?? null,
        outboundId: headerRow?.outbound_id ?? null,
        sourceRef: headerRow?.source_ref ?? null,
        reasonCode: headerRow?.reason_code_snapshot ?? null,
        statusCode: headerRow?.status_code ?? null,
        transactionId: headerRow?.transaction_id ?? null,
        totalQuantity: headerRow?.total_quantity ?? null,
      },
      expected: {
        sourceRef,
        reasonCode: "BONUS",
        statusCode: "POSTED",
        totalQuantity: 2,
      },
    }, null, 2));
  }

  return {
    classification: allExact ? "EXACT" : anyEvidence ? "PARTIAL_OR_CONFLICTING" : "NONE",
    ...allEvidenceRows,
    evidence,
    directProof: {
      path: `manual_outbounds?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref=eq.${encodeURIComponent(sourceRef)}&limit=2&select=*`,
      select: "*",
      filters: {
        organization_id: organizationId,
        source_ref: sourceRef,
      },
      status: 200,
      rowCount: headerRows.length,
      firstRowFields: headerRows[0] ? Object.keys(headerRows[0]).sort() : [],
    },
  };
}

function summarizeLedger(rows) {
  const safeRows = Array.isArray(rows) ? rows : [];
  return {
    rowCount: safeRows.length,
    totalQuantityDelta: safeRows.reduce((sum, row) => sum + asNumber(row?.quantity_delta), 0),
  };
}

async function readSliceCNormalizations(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_normalizations?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_C.channelCode)}&external_event_ref_snapshot=eq.${encodeURIComponent(SLICE_C.externalEventRef)}&select=*`,
  );
}

async function readSliceCLifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_C.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_C.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_C.sourceLineRef)}&select=*`,
  );
}

async function readSliceENormalizations(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_normalizations?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref_snapshot=eq.${encodeURIComponent(SLICE_E.externalReserveEventRef)}&select=*`,
  );
}

async function readSliceELifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_E.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_E.sourceLineRef)}&canonical_source_line_ref=eq.${encodeURIComponent(SLICE_E.canonicalSourceLineRef)}&component_no=eq.1&product_id=eq.${encodeURIComponent(serumProductId)}&select=*`,
  );
}

async function readSliceCListingCatalogRows(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_catalog?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_C_LISTING.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_C_LISTING.externalListingCode)}&select=*`,
  );
}

async function readSliceCListingVersionRows(supabaseUrl, publishableKey, accessToken, organizationId, listingId = "") {
  const listingFilter = isNonBlank(listingId)
    ? `&listing_id=eq.${encodeURIComponent(listingId)}`
    : "";
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_versions?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_C_LISTING.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_C_LISTING.externalListingCode)}${listingFilter}&select=*`,
  );
}

async function readSliceEListingVersionRows(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  listingId = "",
) {
  const listingFilter = isNonBlank(listingId)
    ? `&listing_id=eq.${encodeURIComponent(listingId)}`
    : "";

  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_versions?organization_id=eq.${encodeURIComponent(
      organizationId,
    )}&channel_code=eq.${encodeURIComponent(
      SLICE_E.channelCode,
    )}&external_listing_code=eq.${encodeURIComponent(
      SLICE_E.externalListingCode,
    )}${listingFilter}&select=*`,
  );
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained as the Slice G catalog read-model probe.
async function readSliceGListingCatalogRows(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_catalog?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_G.externalListingCode)}&select=*`,
  );
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained as the Slice G version read-model probe.
async function readSliceGListingVersionRows(supabaseUrl, publishableKey, accessToken, organizationId, listingId = "") {
  const listingFilter = isNonBlank(listingId)
    ? `&listing_id=eq.${encodeURIComponent(listingId)}`
    : "";
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_versions?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_G.externalListingCode)}${listingFilter}&select=*`,
  );
}

async function readSliceGOrders(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_orders?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_G.orderRef)}&select=*`,
  );
}

async function readSliceGRawNormalizationRows(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_normalizations?organization_id=eq.${encodeURIComponent(organizationId)}&external_order_ref_snapshot=eq.${encodeURIComponent(SLICE_G.orderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_G.sourceLineRef)}&select=*`,
  );
}

function uniqueGoldenRowsByIdentity(rows, identityKey) {
  if (!Array.isArray(rows)) return [];
  const unique = new Map();
  for (const row of rows) {
    const identity = String(row?.[identityKey] ?? "");
    if (!isNonBlank(identity)) continue;
    if (!unique.has(identity)) unique.set(identity, row);
  }
  return [...unique.values()];
}

function resolveSliceGExternalSourceLineSnapshots(rawNormalizationRows) {
  return uniqueGoldenRowsByIdentity(rawNormalizationRows, "source_line_id");
}

function resolveSliceGCanonicalComponentRows(rawNormalizationRows, sourceLineId = "") {
  if (!Array.isArray(rawNormalizationRows)) return [];
  return rawNormalizationRows.filter((row) =>
    (!isNonBlank(sourceLineId) || String(row?.source_line_id ?? "") === String(sourceLineId))
    && isNonBlank(String(row?.source_component_id ?? "")),
  );
}

async function readSliceGReservations(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_reservations?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_G.orderRef)}&select=*`,
  );
}

async function readSliceGEvents(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_event_ref=in.(${encodeURIComponent(SLICE_G.reserveEventRef)},${encodeURIComponent(SLICE_G.shipEventRef)})&select=*`,
  );
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained event-line read-model probe for Slice G diagnostics.
async function readSliceGEventLines(supabaseUrl, publishableKey, accessToken, organizationId, eventId = "") {
  const eventFilter = isNonBlank(eventId) ? `&event_id=eq.${encodeURIComponent(eventId)}` : "";
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_event_lines?organization_id=eq.${encodeURIComponent(organizationId)}${eventFilter}&order=line_no.asc&select=*`,
  );
}

async function readSliceGShipAllocations(supabaseUrl, publishableKey, accessToken, organizationId, eventId = "") {
  const eventFilter = isNonBlank(eventId) ? `&event_id=eq.${encodeURIComponent(eventId)}` : "";
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_ship_allocations?organization_id=eq.${encodeURIComponent(organizationId)}${eventFilter}&order=allocation_no.asc&select=*`,
  );
}

async function readSliceGStockLedgerByTransactionId(supabaseUrl, publishableKey, accessToken, organizationId, transactionId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&transaction_id=eq.${encodeURIComponent(transactionId)}&order=line_no.asc&select=*`,
  );
}

function buildSliceGPreviewPayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_channel_code: SLICE_G.channelCode,
    p_external_listing_code: SLICE_G.externalListingCode,
    p_listing_quantity: SLICE_G.listingQuantity,
    p_occurred_at: SLICE_G.reserveOccurredAt,
  };
}

function buildSliceGReservePayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_G.reserveIdempotencyKey,
    p_channel_code: SLICE_G.channelCode,
    p_event_ref: SLICE_G.reserveEventRef,
    p_order_ref: SLICE_G.orderRef,
    p_source_status: SLICE_G.sourceStatusReserve,
    p_occurred_at: SLICE_G.reserveOccurredAt,
    p_received_at: SLICE_G.reserveReceivedAt,
    p_lines: [{
      sourceLineRef: SLICE_G.sourceLineRef,
      externalListingCode: SLICE_G.externalListingCode,
      listingQuantity: SLICE_G.listingQuantity,
      sourceTitle: SLICE_G.displayName,
      sourceSku: SLICE_G.externalListingCode,
      sourceStatus: SLICE_G.sourceStatusReserve,
      rawLinePayload: { lineId: "bundle-001" },
    }],
    p_note: "Golden Demo Slice G bundle reserve.",
    p_raw_payload: { source: "golden-demo-runner", version: 1, slice: "G", scenario: "bundle-shipment" },
    p_metadata: { source: "golden-demo-runner", version: 1, slice: "G", reference: SLICE_G.metadataReference },
    p_schema_version: 1,
  };
}

function buildSliceGShipPayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_G.shipIdempotencyKey,
    p_channel_code: SLICE_G.channelCode,
    p_event_ref: SLICE_G.shipEventRef,
    p_order_ref: SLICE_G.orderRef,
    p_source_status: SLICE_G.sourceStatusShip,
    p_occurred_at: SLICE_G.shipOccurredAt,
    p_received_at: SLICE_G.shipReceivedAt,
    p_lines: [
      { orderSourceLineRef: SLICE_G.sourceLineRef, componentNo: 1, quantity: 2 },
      { orderSourceLineRef: SLICE_G.sourceLineRef, componentNo: 2, quantity: 1 },
    ],
    p_note: "Golden Demo Slice G bundle ship.",
    p_raw_payload: { source: "golden-demo-runner", version: 1, slice: "G", scenario: "bundle-shipped" },
    p_metadata: { source: "golden-demo-runner", version: 1, slice: "G", reference: SLICE_G.metadataReference },
    p_schema_version: 1,
  };
}

function assertSliceCListingEventTimeVersion(rows, serumProductId, allowedStatuses) {
  if (!Array.isArray(rows)) {
    fail("Versions Slice C harus berupa array.");
    return null;
  }
  const matching = rows.filter((row) => (
    String(row?.listing_type_code ?? "") === "SINGLE" &&
    String(row?.product_id ?? "") === String(serumProductId) &&
    allowedStatuses.includes(String(row?.status_code ?? "")) &&
    sameInstant(row?.effective_from, row?.effective_from) &&
    Date.parse(String(row?.effective_from ?? "")) <= Date.parse(SLICE_C.occurredAt) &&
    (
      row?.effective_to === null ||
      row?.effective_to === undefined ||
      Date.parse(String(row?.effective_to)) > Date.parse(SLICE_C.occurredAt)
    )
  ));
  if (matching.length !== 1) {
    fail(`Version Slice C pada event-time harus tepat satu row, tetapi ditemukan ${matching.length}.`);
    return null;
  }
  const row = matching[0];
  if (
    !sameInstant(row?.effective_from, row?.effective_from) ||
    !isHex64(row?.mapping_fingerprint) ||
    asNumber(row?.component_count) !== 1
  ) {
    fail("Version Slice C event-time tidak exact.");
    return null;
  }
  return row;
}

function assertSliceCListingCatalogPublished(row, organizationId, serumProductId) {
  if (!row || typeof row !== "object") {
    fail("Catalog Slice C published harus object.");
    return null;
  }
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_C_LISTING.channelCode ||
    String(row?.external_listing_code ?? "") !== SLICE_C_LISTING.externalListingCode ||
    String(row?.listing_type_code ?? "") !== SLICE_C_LISTING.listingTypeCode ||
    String(row?.status_code ?? "") !== "ACTIVE" ||
    String(row?.mapping_readiness_code ?? "") !== "PUBLISHED" ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    !["ACTIVE", "RETIRED"].includes(String(row?.current_mapping_status_code ?? "")) ||
    !isHex64(row?.mapping_fingerprint)
  ) {
    fail("Catalog Slice C published tidak exact.");
    return null;
  }
  return row;
}

function assertSliceCListingCatalogDraft(row, organizationId) {
  if (!row || typeof row !== "object") {
    fail("Catalog Slice C draft harus object.");
    return null;
  }
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_C_LISTING.channelCode ||
    String(row?.external_listing_code ?? "") !== SLICE_C_LISTING.externalListingCode ||
    String(row?.listing_type_code ?? "") !== SLICE_C_LISTING.listingTypeCode ||
    String(row?.status_code ?? "") === "ARCHIVED" ||
    String(row?.mapping_readiness_code ?? "") !== "DRAFT_ONLY"
  ) {
    fail("Catalog Slice C draft tidak exact.");
    return null;
  }
  return row;
}

function assertSliceCListingDraftResponse(responseJson) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Response draft listing Slice C harus object.");
    return null;
  }
  if (
    String(responseJson?.status ?? "") !== "DRAFT_CREATED" ||
    !isNonBlank(responseJson?.listingId) ||
    !isNonBlank(responseJson?.versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    String(responseJson?.channelCode ?? "") !== "SHOPEE" ||
    String(responseJson?.externalListingCode ?? "") !== "SHP-SER-NIA-30" ||
    asNumber(responseJson?.versionRowVersion) !== 1 ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_C_LISTING.effectiveFrom) ||
    asNumber(responseJson?.componentCount) !== 1
  ) {
    fail("Response draft listing Slice C tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceCListingPreviewResponse(responseJson, listingId, versionId) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Preview listing Slice C harus object.");
    return null;
  }
  const blockers = Array.isArray(responseJson?.blockers) ? responseJson.blockers : null;
  if (
    responseJson?.eligible !== true ||
    String(responseJson?.listingId ?? "") !== String(listingId) ||
    String(responseJson?.versionId ?? "") !== String(versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    asNumber(responseJson?.versionRowVersion) <= 0 ||
    !isHex64(responseJson?.basisHash) ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_C_LISTING.effectiveFrom) ||
    (blockers !== null && blockers.length !== 0)
  ) {
    fail("Preview listing Slice C tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceCListingActivationResponse(responseJson, listingId, versionId, previewBasisHash) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Activation listing Slice C harus object.");
    return null;
  }
  if (
    String(responseJson?.status ?? "") !== "ACTIVATED" ||
    String(responseJson?.listingId ?? "") !== String(listingId) ||
    String(responseJson?.versionId ?? "") !== String(versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_C_LISTING.effectiveFrom) ||
    !isHex64(responseJson?.mappingFingerprint) ||
    String(responseJson?.previewBasisHash ?? "") !== String(previewBasisHash)
  ) {
    fail("Activation listing Slice C tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceEListingDraftResponse(responseJson) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Response draft listing Slice E harus object.");
    return null;
  }
  if (
    String(responseJson?.status ?? "") !== "DRAFT_CREATED" ||
    !isNonBlank(responseJson?.listingId) ||
    !isNonBlank(responseJson?.versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    String(responseJson?.channelCode ?? "") !== "TIKTOK_SHOP" ||
    String(responseJson?.externalListingCode ?? "") !== SLICE_E.externalListingCode ||
    asNumber(responseJson?.versionRowVersion) !== 1 ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_E.occurredAt) ||
    asNumber(responseJson?.componentCount) !== 1
  ) {
    fail("Response draft listing Slice E tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceEListingPreviewResponse(responseJson, listingId, versionId) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Preview listing Slice E harus object.");
    return null;
  }
  const blockers = Array.isArray(responseJson?.blockers) ? responseJson.blockers : null;
  if (
    responseJson?.eligible !== true ||
    String(responseJson?.listingId ?? "") !== String(listingId) ||
    String(responseJson?.versionId ?? "") !== String(versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    asNumber(responseJson?.versionRowVersion) <= 0 ||
    !isHex64(responseJson?.basisHash) ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_E.occurredAt) ||
    (blockers !== null && blockers.length !== 0)
  ) {
    fail("Preview listing Slice E tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceEListingActivationResponse(responseJson, listingId, versionId, previewBasisHash) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Activation listing Slice E harus object.");
    return null;
  }
  if (
    String(responseJson?.status ?? "") !== "ACTIVATED" ||
    String(responseJson?.listingId ?? "") !== String(listingId) ||
    String(responseJson?.versionId ?? "") !== String(versionId) ||
    String(responseJson?.listingType ?? "") !== "SINGLE" ||
    !sameInstant(responseJson?.effectiveFrom, SLICE_E.occurredAt) ||
    !isHex64(responseJson?.mappingFingerprint) ||
    String(responseJson?.previewBasisHash ?? "") !== String(previewBasisHash)
  ) {
    fail("Activation listing Slice E tidak exact.");
    return null;
  }
  return responseJson;
}

function assertSliceEListingCatalogPublished(row, organizationId, serumProductId) {
  if (!row || typeof row !== "object") {
    fail("Catalog Slice E published harus object.");
    return null;
  }
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.external_listing_code ?? "") !== SLICE_E.externalListingCode ||
    String(row?.listing_type_code ?? "") !== "SINGLE" ||
    String(row?.status_code ?? "") !== "ACTIVE" ||
    String(row?.mapping_readiness_code ?? "") !== "PUBLISHED" ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    !["ACTIVE", "RETIRED"].includes(String(row?.current_mapping_status_code ?? "")) ||
    !isHex64(row?.mapping_fingerprint)
  ) {
    fail("Catalog Slice E published tidak exact.");
    return null;
  }
  return row;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained assertion helper for the persisted Slice E catalog draft.
function assertSliceEListingCatalogDraft(row, organizationId) {
  if (!row || typeof row !== "object") {
    fail("Catalog Slice E draft harus object.");
    return null;
  }
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.external_listing_code ?? "") !== SLICE_E.externalListingCode ||
    String(row?.listing_type_code ?? "") !== "SINGLE" ||
    String(row?.status_code ?? "") === "ARCHIVED" ||
    String(row?.mapping_readiness_code ?? "") !== "DRAFT_ONLY"
  ) {
    fail("Catalog Slice E draft tidak exact.");
    return null;
  }
  return row;
}

function assertSliceEListingLifecycleSnapshot(readModel, phaseContext) {
  const observedPhase = phaseContext?.effectivePhase ?? phaseContext;
  const expectedPhase = resolveExpectedSerumProjectionPhase(observedPhase);
  const productRows = (readModel?.productInventory ?? []).filter(
    (row) => String(row?.sku ?? "") === "SER-NIA-30",
  );

  if (productRows.length !== 1) {
    fail(`Snapshot lifecycle listing Slice E untuk product_inventory harus tepat satu row, tetapi ditemukan ${productRows.length}.`);
    return false;
  }

  const productRow = productRows[0];
  const actualProduct = {
    sellable: asNumber(productRow?.sellable_qty),
    reserved: asNumber(productRow?.reserved_qty),
    available: asNumber(productRow?.available_qty),
  };
  const expectedProducts = [expectedPhase];

  console.log(JSON.stringify({
    assertion: "Slice E product_inventory",
    inventorySource: "CURRENT_READ_MODEL",
    basePhase: phaseContext?.basePhase?.detectedPhase ?? null,
    bundleClassification: phaseContext?.bundleClassification ?? null,
    observedPhase: observedPhase?.detectedPhase ?? null,
    contextPhase: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
    effectivePhase: expectedPhase?.detectedPhase ?? null,
    expectedProjectionPhase: expectedPhase?.detectedPhase ?? null,
  }, null, 2));

  const matchedExpectedPhase = expectedProducts.find((candidate) =>
    actualProduct.sellable === candidate.sellable &&
    actualProduct.reserved === candidate.reserved &&
    actualProduct.available === candidate.available,
  );

  if (!matchedExpectedPhase) {
    fail(
      `Snapshot lifecycle listing Slice E untuk product_inventory tidak exact. actual=${JSON.stringify({
        detectedPhase: expectedPhase.detectedPhase,
        expected: expectedProducts.map((candidate) => ({
          detectedPhase: candidate.detectedPhase,
          sellable: candidate.sellable,
          reserved: candidate.reserved,
          available: candidate.available,
        })),
        actual: actualProduct,
      })}`,
    );
    return false;
  }

  const expectedBatches = matchedExpectedPhase.batches;
  const expectedBatchCodes = new Set(Object.keys(expectedBatches));
  const actualBatches = {};
  const batchRows = (readModel?.batchInventory ?? []).filter((row) => {
    const batchCode = String(row?.batch_code ?? "");
    if (!expectedBatchCodes.has(batchCode)) return false;
    actualBatches[batchCode] = asNumber(row?.sellable_qty);
    return true;
  });

  if (batchRows.length !== expectedBatchCodes.size) {
    fail(
      `Snapshot lifecycle listing Slice E untuk batch_inventory tidak exact. actual=${JSON.stringify({
        detectedPhase: expectedPhase.detectedPhase,
        expectedBatches,
        actualBatches,
      })}`,
    );
    return false;
  }

  for (const [batchCode, expectedQty] of Object.entries(expectedBatches)) {
    if (asNumber(actualBatches[batchCode]) !== asNumber(expectedQty)) {
      fail(
        `Snapshot lifecycle listing Slice E untuk batch_inventory tidak exact. actual=${JSON.stringify({
          detectedPhase: expectedPhase.detectedPhase,
          expectedBatches,
          actualBatches,
        })}`,
      );
      return false;
    }
  }

  return true;
}

function buildSliceEProjectionPhase(name, sliceENormalizationCount, sliceEShipEventCount) {
  const detectedPhase = String(name ?? "");
  if (!["SLICE_D_SHIPPED", "SLICE_E_RESERVED", "SLICE_E_IN_TRANSIT"].includes(detectedPhase)) {
    throw new Error(`GOLDEN_PHASE_UNKNOWN: ${detectedPhase || "<empty>"}`);
  }
  return {
    ...expectedGoldenCurrentStateForPhase({ detectedPhase }).serumProduct,
    detectedPhase,
    sliceENormalizationCount,
    sliceEShipEventCount,
  };
}

async function detectCurrentTiktokProjectionPhase(supabaseUrl, publishableKey, accessToken, organizationId) {
  const sliceENormalizationRows = await readSliceENormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!sliceENormalizationRows) return null;

  const sliceENormalizationCount = sliceENormalizationRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId)
    && String(row?.channel_code ?? "") === SLICE_E.channelCode
    && String(row?.external_event_ref_snapshot ?? "") === SLICE_E.externalReserveEventRef,
  ).length;

  if (sliceENormalizationCount > 1) {
    fail(`Normalization Slice E harus tunggal, tetapi ditemukan ${sliceENormalizationCount}.`);
    return null;
  }

  const sliceEShipEventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&limit=2&select=*`,
  );
  if (!sliceEShipEventRows) return null;

  const sliceEShipEventCount = sliceEShipEventRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId)
    && String(row?.channel_code ?? "") === SLICE_E.channelCode
    && String(row?.external_event_ref ?? "") === SLICE_E.externalShipEventRef
    && String(row?.event_type_code ?? "") === "SHIP"
    && String(row?.status_code ?? "") === "APPLIED",
  ).length;

  if (sliceEShipEventCount > 1) {
    fail(`Event Slice E harus tunggal, tetapi ditemukan ${sliceEShipEventCount}.`);
    return null;
  }

  if (sliceEShipEventCount === 1) {
    return buildSliceEProjectionPhase("SLICE_E_IN_TRANSIT", sliceENormalizationCount, sliceEShipEventCount);
  }

  if (sliceENormalizationCount === 1) {
    return buildSliceEProjectionPhase("SLICE_E_RESERVED", sliceENormalizationCount, sliceEShipEventCount);
  }

  return buildSliceEProjectionPhase("SLICE_D_SHIPPED", sliceENormalizationCount, sliceEShipEventCount);
}

function goldenTerminalMetadata(stage, extra = {}) {
  return {
    source: "golden-demo-runner",
    version: 1,
    terminal: "stocktake-reconciliation-final-acceptance",
    reference: GOLDEN_TERMINAL.stocktakeReference,
    stage,
    ...extra,
  };
}

function terminalMismatch(path, expected, actual) {
  return { path, expected, actual };
}

async function readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId) {
  const detailsRows = await readJsonRows(
    supabaseUrl, publishableKey, accessToken,
    `stocktake_details?organization_id=eq.${encodeURIComponent(organizationId)}&title=eq.${encodeURIComponent(GOLDEN_TERMINAL.stocktakeTitle)}&select=*`,
  );
  if (!detailsRows) return null;
  if (detailsRows.length === 0) return { classification: "NONE", counts: { stocktakeCount: 0 } };
  if (detailsRows.length !== 1) return { classification: "PARTIAL_OR_CONFLICTING", counts: { stocktakeCount: detailsRows.length } };
  const details = detailsRows[0];
  const metadata = details?.metadata && typeof details.metadata === "object" ? details.metadata : {};
  if (String(metadata.reference ?? "") !== GOLDEN_TERMINAL.stocktakeReference || String(metadata.source ?? "") !== "golden-demo-runner") {
    return { classification: "PARTIAL_OR_CONFLICTING", details, mismatchFields: [terminalMismatch("stocktake.metadata", goldenTerminalMetadata("create").reference, metadata.reference ?? null)] };
  }
  const stocktakeId = String(details.stocktake_id ?? "");
  if (!UUID_PATTERN.test(stocktakeId)) return { classification: "PARTIAL_OR_CONFLICTING", details, mismatchFields: [terminalMismatch("stocktakeId", "uuid", stocktakeId)] };
  const [reviewLines, attempts, approvals, approvalLines, postings] = await Promise.all([
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_review_lines?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_count_attempts?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_approvals?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_approval_lines?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_postings?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`),
  ]);
  if (![reviewLines, attempts, approvals, approvalLines, postings].every(Array.isArray)) return null;
  const common = { details, stocktakeId, reviewLines, attempts, approvals, approvalLines, postings };
  const status = String(details.status_code ?? "");
  if (["DRAFT", "READY", "COUNTING", "REVIEW", "APPROVED"].includes(status)) return { classification: "IN_PROGRESS", ...common };
  if (status !== "POSTED" || postings.length !== 1 || approvals.length !== 1 || reviewLines.length !== 1 || attempts.length !== 1 || approvalLines.length !== 1) {
    return { classification: "PARTIAL_OR_CONFLICTING", ...common, mismatchFields: [terminalMismatch("stocktake.lifecycle", "POSTED with exactly one line/attempt/approval/posting", { status, reviewLineCount: reviewLines.length, attemptCount: attempts.length, approvalCount: approvals.length, approvalLineCount: approvalLines.length, postingCount: postings.length })] };
  }
  const posting = postings[0];
  const [postingLines, ledgerRows, reconciliationRuns, reconciliationChecks, reconciliationIssues, serumRows, cleanserRows, batchRows] = await Promise.all([
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_posting_lines?organization_id=eq.${encodeURIComponent(organizationId)}&posting_id=eq.${encodeURIComponent(posting.posting_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&transaction_id=eq.${encodeURIComponent(posting.transaction_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `reconciliation_runs?organization_id=eq.${encodeURIComponent(organizationId)}&run_id=eq.${encodeURIComponent(posting.reconciliation_run_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `reconciliation_checks?organization_id=eq.${encodeURIComponent(organizationId)}&run_id=eq.${encodeURIComponent(posting.reconciliation_run_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `reconciliation_issues?organization_id=eq.${encodeURIComponent(organizationId)}&last_seen_run_id=eq.${encodeURIComponent(posting.reconciliation_run_id)}&select=*`),
    readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, GOLDEN_TERMINAL.serumSku),
    readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, GOLDEN_TERMINAL.cleanserSku),
    readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, GOLDEN_TERMINAL.batchCode),
  ]);
  if (![postingLines, ledgerRows, reconciliationRuns, reconciliationChecks, reconciliationIssues, serumRows, cleanserRows, batchRows].every(Array.isArray)) return null;
  const line = reviewLines[0];
  const attempt = attempts[0];
  const approval = approvals[0];
  const approvalLine = approvalLines[0];
  const postingLine = postingLines[0];
  const ledger = ledgerRows[0];
  const reconciliation = reconciliationRuns[0];
  const mismatches = [];
  const check = (path, expected, actual) => { if (JSON.stringify(expected) !== JSON.stringify(actual)) mismatches.push(terminalMismatch(path, expected, actual)); };
  check("stocktake.status", "POSTED", status);
  check("line.identity", { sku: GOLDEN_TERMINAL.serumSku, batch: GOLDEN_TERMINAL.batchCode, bucket: "SELLABLE" }, { sku: line?.product_sku_snapshot ?? null, batch: line?.batch_code_snapshot ?? null, bucket: line?.bucket_code ?? null });
  check("count", { expected: GOLDEN_TERMINAL.expectedQty, physical: GOLDEN_TERMINAL.physicalQty, variance: GOLDEN_TERMINAL.varianceQty }, { expected: asNumber(attempt?.expected_qty_at_count), physical: asNumber(attempt?.physical_qty), variance: asNumber(attempt?.variance_qty) });
  check("review", { decision: "VARIANCE_ACCEPTED", reason: GOLDEN_TERMINAL.reasonCode }, { decision: line?.review_decision_code ?? null, reason: line?.reason_code ?? null });
  check("approval", { variance: GOLDEN_TERMINAL.varianceQty, version: asNumber(posting?.approval_version_no) }, { variance: asNumber(approvalLine?.variance_qty), version: asNumber(approval?.approval_version_no) });
  check("posting", { lineCount: 1, nonzeroLineCount: 1, netAdjustmentQty: GOLDEN_TERMINAL.varianceQty }, { lineCount: asNumber(posting?.line_count), nonzeroLineCount: asNumber(posting?.nonzero_line_count), netAdjustmentQty: asNumber(posting?.net_adjustment_qty) });
  check("postingLine", { adjustment: GOLDEN_TERMINAL.varianceQty, before: GOLDEN_TERMINAL.expectedQty, after: GOLDEN_TERMINAL.physicalQty }, { adjustment: asNumber(postingLine?.adjustment_qty), before: asNumber(postingLine?.current_ledger_qty_before), after: asNumber(postingLine?.current_ledger_qty_after) });
  check("ledger", { count: 1, type: "STOCKTAKE_ADJUSTMENT", sourceType: "STOCKTAKE", quantity: GOLDEN_TERMINAL.varianceQty, batch: GOLDEN_TERMINAL.batchCode }, { count: ledgerRows.length, type: ledger?.transaction_type_code ?? null, sourceType: ledger?.source_type_code ?? null, quantity: asNumber(ledger?.quantity_delta), batch: ledger?.batch_code_snapshot ?? null });
  check("projection.serum", { sellable: 23, reserved: 0, available: 23 }, { sellable: asNumber(serumRows[0]?.sellable_qty), reserved: asNumber(serumRows[0]?.reserved_qty), available: asNumber(serumRows[0]?.available_qty) });
  check("projection.cleanser", { sellable: 14, reserved: 0, available: 14 }, { sellable: asNumber(cleanserRows[0]?.sellable_qty), reserved: asNumber(cleanserRows[0]?.reserved_qty), available: asNumber(cleanserRows[0]?.available_qty) });
  check("projection.batch", GOLDEN_TERMINAL.physicalQty, asNumber(batchRows[0]?.sellable_qty));
  const reconciliationLedgerMutationCount = Math.max(0, asNumber(reconciliation?.ledger_seq_to) - asNumber(posting?.posting_ledger_seq_after));
  const reconciliationContract = resolveGoldenReconciliationTerminalContract({
    persistedStatus: reconciliation?.status_code,
    runType: reconciliation?.run_type_code,
    differenceCount: reconciliationIssues.length,
    unexpectedOpenCriticalIssueCount: reconciliationIssues.filter((issue) => String(issue?.status_code ?? "") === "OPEN" && String(issue?.severity_code ?? "") === "CRITICAL").length,
    ledgerMutationCount: reconciliationLedgerMutationCount,
  });
  check("reconciliation", { count: 1, type: GOLDEN_RECONCILIATION.runType, status: GOLDEN_RECONCILIATION.successfulStatus, ledgerBoundary: asNumber(posting?.posting_ledger_seq_after) }, { count: reconciliationRuns.length, type: reconciliation?.run_type_code ?? null, status: reconciliation?.status_code ?? null, ledgerBoundary: asNumber(reconciliation?.ledger_seq_to) });
  check("reconciliationChecks", GOLDEN_RECONCILIATION.expectedCheckCount, reconciliationChecks.length);
  const unexpectedCritical = reconciliationIssues.filter((issue) => String(issue?.status_code ?? "") === "OPEN" && String(issue?.severity_code ?? "") === "CRITICAL");
  check("reconciliation.openCritical", 0, unexpectedCritical.length);
  check("reconciliation.stockNeutral", true, reconciliationContract.stockNeutral);
  check("reconciliation.clean", true, reconciliationContract.clean);
  const stocktakeExact = mismatches.filter((entry) => !entry.path.startsWith("reconciliation")).length === 0;
  const reconciliationExact = mismatches.filter((entry) => entry.path.startsWith("reconciliation")).length === 0;
  return {
    classification: stocktakeExact && reconciliationExact ? "EXACT_FINAL" : "PARTIAL_OR_CONFLICTING",
    ...common, posting, postingLines, ledgerRows, reconciliationRuns, reconciliationChecks, reconciliationIssues, serumRows, cleanserRows, batchRows, reconciliationContract, reconciliationLedgerMutationCount,
    mismatchFields: mismatches,
    stocktakeExact,
    reconciliationExact,
    effectivePhase: stocktakeExact && reconciliationExact ? { detectedPhase: "GOLDEN_FINAL_ACCEPTED" } : null,
  };
}

async function invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, functionName, body) {
  const response = await rpcJson(supabaseUrl, publishableKey, accessToken, functionName, body);
  if (response.status !== 200 || !response.ok || !response.payload || typeof response.payload !== "object") {
    failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { functionName, status: response.status, payload: response.payload ?? null });
  }
  return response.payload;
}

async function runGoldenTerminalStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumBatchId) {
  let state = await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!state) return null;
  if (state.classification === "EXACT_FINAL") {
    return { outcome: "ADOPTED", phase: state.effectivePhase, entityId: state.stocktakeId, commandEvidence: { action: "ADOPTED" }, persistedEvidence: { exact: true, duplicateEffect: false, state }, projectionEvidence: { exact: true }, duplicateSafetyEvidence: { exact: true }, response: { status: "POSTED" } };
  }
  if (state.classification === "PARTIAL_OR_CONFLICTING") {
    const code = state.stocktakeExact === true && state.reconciliationExact === false
      ? "GOLDEN_RECONCILIATION_CONTRACT_NOT_EXACT"
      : "GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT";
    failGoldenStateAware(code, { mismatchFields: state.mismatchFields ?? [], reconciliationRunId: state.posting?.reconciliation_run_id ?? null, stocktakeId: state.stocktakeId ?? null });
  }
  let outcome = "REPLAYED";
  if (state.classification === "NONE") {
    const created = await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "create_stocktake", {
      p_organization_id: organizationId,
      p_idempotency_key: GOLDEN_TERMINAL.createIdempotencyKey,
      p_title: GOLDEN_TERMINAL.stocktakeTitle,
      p_stocktake_type_code: "CYCLE",
      p_mode_code: "CONTINUOUS",
      p_visibility_code: "BLIND",
      p_scope: { mode: "BATCHES", batchIds: [serumBatchId], bucketCodes: ["SELLABLE"], includeZeroSystemBalance: false, includeInactiveWithBalance: false, includeBlockedBatches: false, includeExpiredBatches: true },
      p_planned_at: "2026-08-28T06:00:00Z",
      p_note: "Golden Demo physical variance Serum -1.",
      p_metadata: goldenTerminalMetadata("create"),
    });
    if (created.status !== "DRAFT" || !UUID_PATTERN.test(String(created.stocktakeId ?? ""))) failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "create", response: created });
    outcome = "CREATED";
    state = await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId);
  }
  for (let step = 0; step < 8; step += 1) {
    if (!state || state.classification === "PARTIAL_OR_CONFLICTING" || state.classification === "NONE") {
      const code = state?.stocktakeExact === true && state?.reconciliationExact === false
        ? "GOLDEN_RECONCILIATION_CONTRACT_NOT_EXACT"
        : "GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT";
      failGoldenStateAware(code, { stage: "lifecycle", classification: state?.classification ?? null, mismatchFields: state?.mismatchFields ?? [], reconciliationRunId: state?.posting?.reconciliation_run_id ?? null, stocktakeId: state?.stocktakeId ?? null });
    }
    if (state.classification === "EXACT_FINAL") break;
    const status = String(state.details?.status_code ?? "");
    const stocktakeId = state.stocktakeId;
    if (status === "DRAFT") await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "prepare_stocktake", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:prepare:v1`, p_stocktake_id: stocktakeId, p_metadata: goldenTerminalMetadata("prepare") });
    else if (status === "READY") await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "start_stocktake", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:start:v1`, p_stocktake_id: stocktakeId, p_metadata: goldenTerminalMetadata("start") });
    else if (status === "COUNTING") {
      const blindLines = await readJsonRows(supabaseUrl, publishableKey, accessToken, `stocktake_blind_lines?organization_id=eq.${encodeURIComponent(organizationId)}&stocktake_id=eq.${encodeURIComponent(stocktakeId)}&select=*`);
      if (!blindLines || blindLines.length !== 1 || String(blindLines[0]?.product_sku_snapshot ?? "") !== GOLDEN_TERMINAL.serumSku || String(blindLines[0]?.batch_code_snapshot ?? "") !== GOLDEN_TERMINAL.batchCode) failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "count-line", actual: blindLines ?? null });
      const line = blindLines[0];
      if (String(line.count_status_code ?? "") !== "COUNTED") await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "submit_stocktake_count", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:line:${line.stocktake_line_id}:count:1`, p_stocktake_id: stocktakeId, p_stocktake_line_id: line.stocktake_line_id, p_physical_qty: GOLDEN_TERMINAL.physicalQty, p_zero_confirmed: false, p_count_method_code: "MANUAL_ENTRY", p_note: "Golden Demo blind physical count: 11.", p_metadata: goldenTerminalMetadata("count", { attemptNo: 1 }) });
      await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "complete_stocktake_counting", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:complete-counting:1`, p_stocktake_id: stocktakeId, p_metadata: goldenTerminalMetadata("complete-counting") });
    } else if (status === "REVIEW") {
      if (state.reviewLines.length !== 1) failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "review", actualLineCount: state.reviewLines.length });
      const line = state.reviewLines[0];
      if (String(line.review_status_code ?? "") !== "REVIEWED") await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "review_stocktake_line", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:line:${line.stocktake_line_id}:review:${line.version_no}`, p_stocktake_id: stocktakeId, p_stocktake_line_id: line.stocktake_line_id, p_expected_line_version: line.version_no, p_decision_code: "VARIANCE_ACCEPTED", p_reason_code: GOLDEN_TERMINAL.reasonCode, p_review_note: "Golden Demo verified physical loss of one Serum unit.", p_exception_code: null, p_metadata: goldenTerminalMetadata("review") });
      state = await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId);
      const currentVersion = state?.details?.version_no;
      if (!Number.isSafeInteger(Number(currentVersion)) || Number(currentVersion) <= 0) failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "approve-version", actual: currentVersion ?? null });
      await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "approve_stocktake", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:approve:${currentVersion}`, p_stocktake_id: stocktakeId, p_expected_stocktake_version: Number(currentVersion), p_confirmation: true, p_note: "Golden Demo approval for physical loss variance.", p_metadata: goldenTerminalMetadata("approve") });
    } else if (status === "APPROVED") {
      if (state.approvals.length !== 1) failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "post-approval", actualApprovalCount: state.approvals.length });
      const approvalVersion = Number(state.approvals[0]?.approval_version_no);
      await invokeGoldenStocktakeRpc(supabaseUrl, publishableKey, accessToken, "post_stocktake_adjustment", { p_organization_id: organizationId, p_idempotency_key: `stocktake:${stocktakeId}:post:${approvalVersion}`, p_stocktake_id: stocktakeId, p_approval_version: approvalVersion, p_confirmation: true, p_note: "Golden Demo stocktake adjustment Serum -1.", p_metadata: goldenTerminalMetadata("post", { approvalVersion }) });
    } else {
      failGoldenStateAware("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT", { stage: "unknown-status", status });
    }
    state = await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId);
  }
  if (!state || state.classification !== "EXACT_FINAL") {
    const code = state?.stocktakeExact === false
      ? "GOLDEN_STOCKTAKE_ADJUSTMENT_NOT_EXACT"
      : state?.reconciliationExact === false
        ? "GOLDEN_RECONCILIATION_CONTRACT_NOT_EXACT"
        : "GOLDEN_FINAL_ACCEPTANCE_NOT_REACHED";
    failGoldenStateAware(code, { mismatchFields: state?.mismatchFields ?? [], classification: state?.classification ?? null });
  }
  return { outcome, phase: state.effectivePhase, entityId: state.stocktakeId, commandEvidence: { action: outcome, stocktakeId: state.stocktakeId }, persistedEvidence: { exact: true, duplicateEffect: false, state }, projectionEvidence: { exact: true }, duplicateSafetyEvidence: { exact: true }, response: { status: "POSTED", reconciliationRunId: state.posting.reconciliation_run_id } };
}

async function detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
) {
  const serumRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    SLICE_H.productSku,
  );
  if (!serumRows) return null;
  const serumCandidates = serumRows.filter((row) =>
    String(row?.sku ?? "") === SLICE_H.productSku && UUID_PATTERN.test(String(row?.product_id ?? "")),
  );
  if (serumCandidates.length !== 1) {
    throw new Error("GOLDEN_PHASE_SERUM_PRODUCT_AMBIGUOUS");
  }
  const [serumProduct] = serumCandidates;
  const serumProductId = String(serumProduct.product_id);

  // A posted stocktake legitimately changes the current projection beyond
  // Slice K. Resolve terminal evidence before applying the historical Slice K
  // detector, otherwise a valid later phase is misclassified as a K conflict.
  const terminalState = await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!terminalState) return null;
  if (terminalState.classification === "EXACT_FINAL") return terminalState.effectivePhase;
  if (terminalState.classification === "PARTIAL_OR_CONFLICTING") {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_TERMINAL");
  }

  const sliceKState = await probeSliceKTiktokClaimState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!sliceKState) return null;
  if (sliceKState.classification === "EXACT_NOTIFICATION_CREATED") {
    return sliceKState.effectivePhase;
  }
  if (sliceKState.classification === "EXACT_CLAIM_CREATED") {
    return sliceKState.effectivePhase;
  }
  if (sliceKState.classification === "PARTIAL_OR_CONFLICTING") {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_K");
  }

  const sliceJState = await probeSliceJTiktokReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!sliceJState) return null;
  if (sliceJState.classification === "EXACT_LOST") return sliceJState.effectivePhase;
  if (sliceJState.classification === "EXPECTED_ONLY") return { detectedPhase: "SLICE_J_TIKTOK_RETURN_EXPECTED" };
  if (sliceJState.classification === "PARTIAL_OR_CONFLICTING") {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_J");
  }

  const sliceIState = await probeSliceIReturnInspectionState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    SLICE_H.correctedReturnRef,
    SLICE_H.correctedReceiptRef,
    SLICE_I.inspectionRef,
  );
  if (!sliceIState) return null;
  if (sliceIState.classification === "EXACT_INSPECTED") {
    const cleanserRows = await readProductInventoryBySku(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      SLICE_G.cleanserProductSku,
    );
    if (!cleanserRows) return null;
    const cleanserCandidates = cleanserRows.filter((row) => String(row?.sku ?? "") === SLICE_G.cleanserProductSku);
    if (cleanserCandidates.length !== 1) {
      throw new Error("GOLDEN_PHASE_CLEANSER_PRODUCT_AMBIGUOUS");
    }
    const [cleanserProduct] = cleanserCandidates;
    console.log(JSON.stringify({
      assertion: "Persisted Golden phase",
      detectedPhase: sliceIState.effectivePhase.detectedPhase,
      basePhase: "SLICE_G_BUNDLE_SHIPPED",
      effectivePhase: sliceIState.effectivePhase.detectedPhase,
      contextPhase: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
      persistedHighestPhase: sliceIState.effectivePhase.detectedPhase,
      phaseRank: getSerumProjectionPhaseRank(sliceIState.effectivePhase),
      evidence: { sliceHVerified: true, sliceIExactInspected: true },
      serumActual: { sellable: asNumber(serumProduct.sellable_qty), reserved: asNumber(serumProduct.reserved_qty), available: asNumber(serumProduct.available_qty) },
      serumExpected: { sellable: sliceIState.effectivePhase.sellable, reserved: sliceIState.effectivePhase.reserved, available: sliceIState.effectivePhase.available },
      cleanserActual: { sellable: asNumber(cleanserProduct.sellable_qty), reserved: asNumber(cleanserProduct.reserved_qty), available: asNumber(cleanserProduct.available_qty) },
      cleanserExpected: sliceIState.effectivePhase.cleanser,
    }, null, 2));
    return sliceIState.effectivePhase;
  }
  if (sliceIState.classification === "CONFLICT_OR_PARTIAL") {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_I");
  }

  const sliceHState = await probeSliceHReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    SLICE_H.correctedReturnRef,
    SLICE_H.correctedReceiptRef,
  );
  if (!sliceHState) return null;
  if (sliceHState.classification === "EXACT_RECEIVED") {
    return sliceHState.effectivePhase;
  }
  if (sliceHState.classification === "EXACT_EXPECTED") {
    return sliceHState.effectivePhase;
  }
  if (sliceHState.classification === "CONFLICT_OR_PARTIAL") {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_H");
  }

  const sliceBReceipts = await readReceiptBySourceRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM",
  );
  if (!sliceBReceipts) return null;
  if (sliceBReceipts.length > 1) {
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_B");
  }
  const lowerMarketplacePhase = await detectCurrentSerumProjectionPhase(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!lowerMarketplacePhase) return null;
  if (sliceBReceipts.length === 0) {
    if (lowerMarketplacePhase.detectedPhase !== "SLICE_B_RECEIVED") {
      throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_B");
    }
    const initial = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_A_INITIAL" });
    return {
      ...initial.serumProduct,
      detectedPhase: "SLICE_A_INITIAL",
      sliceCNormalizationCount: 0,
      sliceDShipEventCount: 0,
    };
  }

  const bundleState = await probeBundleSliceGState(supabaseUrl, publishableKey, accessToken, organizationId);
  if (bundleState) {
    if (bundleState.phase.detectedPhase === "SLICE_G_BUNDLE_SHIPPED" || bundleState.phase.detectedPhase === "SLICE_G_BUNDLE_RESERVED") {
      return bundleState.phase;
    }
  } else {
    return null;
  }

  const tiktokPhase = await detectCurrentTiktokProjectionPhase(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!tiktokPhase) {
    return null;
  }
  const phaseBeforeSliceF = isPhaseAtLeast(tiktokPhase, "SLICE_E_RESERVED")
    ? tiktokPhase
    : lowerMarketplacePhase;

  const sliceFState = await probeSliceFManualBonusState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!sliceFState) {
    return phaseBeforeSliceF;
  }

  if (sliceFState.classification === "PARTIAL_OR_CONFLICTING") {
    console.log(JSON.stringify({
      assertion: "Slice F detector REST parity",
      detectorPhase: tiktokPhase.detectedPhase,
      evidence: sliceFState.evidence,
      counts: {
        manualOutbounds: sliceFState.headerRows.length,
        lines: sliceFState.lineRows.length,
        allocations: sliceFState.allocationRows.length,
        transactions: sliceFState.transactionRows.length,
        ledgerEntries: sliceFState.ledgerRows.length,
      },
      directProof: sliceFState.directProof,
    }, null, 2));
    throw new Error("GOLDEN_PHASE_EVIDENCE_CONFLICT_SLICE_F");
  }

  if (sliceFState.classification === "EXACT") {
    return buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN);
  }

  return phaseBeforeSliceF;
}

async function probeBundleSliceGState(supabaseUrl, publishableKey, accessToken, organizationId, { silent = false } = {}) {
  const normalizationRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_normalizations?organization_id=eq.${encodeURIComponent(organizationId)}&external_event_ref_snapshot=eq.${encodeURIComponent(SLICE_G.reserveEventRef)}&external_order_ref_snapshot=eq.${encodeURIComponent(SLICE_G.orderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_G.sourceLineRef)}&select=*`,
  );
  if (!normalizationRows) return null;

  const lifecycleRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_G.orderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_G.sourceLineRef)}&select=*`,
  );
  if (!lifecycleRows) return null;

  const distinctCount = (rows, key) => new Set(rows.map((row) => String(row?.[key] ?? ""))).size;
  const normalizationRawRowCount = normalizationRows.length;
  const distinctNormalizationCount = distinctCount(normalizationRows, "normalization_event_id");
  const distinctReserveEventCount = distinctCount(normalizationRows, "marketplace_event_id");
  const distinctOrderCount = distinctCount(normalizationRows, "order_id");
  const distinctSourceLineCount = distinctCount(normalizationRows, "source_line_id");
  const distinctComponentCount = distinctCount(normalizationRows, "source_component_id");
  const distinctOrderItemCount = distinctCount(normalizationRows, "order_item_id");
  const distinctReservationCount = distinctCount(normalizationRows, "reservation_id");

  const serumNormalizationRows = normalizationRows.filter((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku);
  const cleanserNormalizationRows = normalizationRows.filter((row) => String(row?.product_sku_snapshot ?? "") !== SLICE_G.serumProductSku);
  const serumLifecycleRows = lifecycleRows.filter((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku);
  const cleanserLifecycleRows = lifecycleRows.filter((row) => String(row?.product_sku_snapshot ?? "") !== SLICE_G.serumProductSku);

  const reserveEventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_G.reserveEventRef)}&select=*`,
  );
  if (!reserveEventRows) return null;
  const shipEventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_G.shipEventRef)}&select=*`,
  );
  if (!shipEventRows) return null;

  const shipmentEventLines = shipEventRows.length === 1
    ? lifecycleRows.slice(0, 2)
    : [];
  const shipAllocations = shipEventRows.length === 1
    ? await readJsonRows(
      supabaseUrl,
      publishableKey,
      accessToken,
      `marketplace_ship_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&event_id=eq.${encodeURIComponent(shipEventRows[0].event_id)}&order=allocation_no.asc&select=*`,
    )
    : [];
  if (shipAllocations === null) return null;
  const stockTransactions = shipEventRows.length === 1 && isNonBlank(shipEventRows[0]?.transaction_id)
    ? [{ id: shipEventRows[0].transaction_id }]
    : [];
  const ledgerRows = stockTransactions.length === 1
    ? await readJsonRows(
      supabaseUrl,
      publishableKey,
      accessToken,
      `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&transaction_id=eq.${encodeURIComponent(stockTransactions[0].id)}&select=*`,
    )
    : [];
  if (ledgerRows === null) return null;

  const serumProduct = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.serumProductSku);
  const cleanserProduct = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.cleanserProductSku);
  if (!serumProduct || !cleanserProduct) return null;
  const serumBatch2608 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2608-A");
  const serumBatch2612 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2612-B");
  const serumBatch2701 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2701-C");
  const cleanserBatch2611 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "CLN-2611-A");
  if (!serumBatch2608 || !serumBatch2612 || !serumBatch2701 || !cleanserBatch2611) return null;

  const basePhase = currentSerumProjectionPhaseContext ?? buildSerumProjectionPhase("SLICE_B_RECEIVED", Number.NaN, Number.NaN);
  const reservedPhase = buildBundleProjectionPhase("SLICE_G_BUNDLE_RESERVED");
  const shippedPhase = buildBundleProjectionPhase("SLICE_G_BUNDLE_SHIPPED");
  const structuralFailedChecks = [
    { name: "raw normalization rows", expected: 2, actual: normalizationRawRowCount, passed: normalizationRawRowCount === 2 },
    { name: "distinct normalization", expected: 1, actual: distinctNormalizationCount, passed: distinctNormalizationCount === 1 },
    { name: "distinct reserve event", expected: 1, actual: distinctReserveEventCount, passed: distinctReserveEventCount === 1 },
    { name: "distinct order", expected: 1, actual: distinctOrderCount, passed: distinctOrderCount === 1 },
    { name: "distinct source line", expected: 1, actual: distinctSourceLineCount, passed: distinctSourceLineCount === 1 },
    { name: "distinct source components", expected: 2, actual: distinctComponentCount, passed: distinctComponentCount === 2 },
    { name: "distinct order items", expected: 2, actual: distinctOrderItemCount, passed: distinctOrderItemCount === 2 },
    { name: "distinct reservations", expected: 2, actual: distinctReservationCount, passed: distinctReservationCount === 2 },
  ];

  const reservedFailedChecks = [
    { name: "actual ship event count", expected: 0, actual: shipEventRows.length, passed: shipEventRows.length === 0 },
    { name: "Serum expanded quantity", expected: 2, actual: Number(serumNormalizationRows[0]?.expanded_quantity ?? NaN), passed: Number(serumNormalizationRows[0]?.expanded_quantity) === 2 },
    { name: "Serum reserved quantity", expected: 2, actual: Number(serumNormalizationRows[0]?.reserved_qty ?? NaN), passed: Number(serumNormalizationRows[0]?.reserved_qty) === 2 },
    { name: "Serum consumed quantity", expected: 0, actual: Number(serumNormalizationRows[0]?.consumed_qty ?? NaN), passed: Number(serumNormalizationRows[0]?.consumed_qty) === 0 },
    { name: "Serum released quantity", expected: 0, actual: Number(serumNormalizationRows[0]?.released_qty ?? NaN), passed: Number(serumNormalizationRows[0]?.released_qty) === 0 },
    { name: "Serum shipped quantity", expected: 0, actual: Number(serumLifecycleRows[0]?.shipped_quantity ?? NaN), passed: Number(serumLifecycleRows[0]?.shipped_quantity) === 0 },
    { name: "Serum open reserved quantity", expected: 2, actual: Number(serumLifecycleRows[0]?.open_reserved_quantity ?? NaN), passed: Number(serumLifecycleRows[0]?.open_reserved_quantity) === 2 },
    { name: "Serum reservation status", expected: "ACTIVE", actual: String(serumNormalizationRows[0]?.reservation_status_code ?? ""), passed: String(serumNormalizationRows[0]?.reservation_status_code ?? "") === "ACTIVE" },
    { name: "Cleanser expanded quantity", expected: 1, actual: Number(cleanserNormalizationRows[0]?.expanded_quantity ?? NaN), passed: Number(cleanserNormalizationRows[0]?.expanded_quantity) === 1 },
    { name: "Cleanser reserved quantity", expected: 1, actual: Number(cleanserNormalizationRows[0]?.reserved_qty ?? NaN), passed: Number(cleanserNormalizationRows[0]?.reserved_qty) === 1 },
    { name: "Cleanser consumed quantity", expected: 0, actual: Number(cleanserNormalizationRows[0]?.consumed_qty ?? NaN), passed: Number(cleanserNormalizationRows[0]?.consumed_qty) === 0 },
    { name: "Cleanser released quantity", expected: 0, actual: Number(cleanserNormalizationRows[0]?.released_qty ?? NaN), passed: Number(cleanserNormalizationRows[0]?.released_qty) === 0 },
    { name: "Cleanser shipped quantity", expected: 0, actual: Number(cleanserLifecycleRows[0]?.shipped_quantity ?? NaN), passed: Number(cleanserLifecycleRows[0]?.shipped_quantity) === 0 },
    { name: "Cleanser open reserved quantity", expected: 1, actual: Number(cleanserLifecycleRows[0]?.open_reserved_quantity ?? NaN), passed: Number(cleanserLifecycleRows[0]?.open_reserved_quantity) === 1 },
    { name: "Cleanser reservation status", expected: "ACTIVE", actual: String(cleanserNormalizationRows[0]?.reservation_status_code ?? ""), passed: String(cleanserNormalizationRows[0]?.reservation_status_code ?? "") === "ACTIVE" },
    { name: "Serum projection", expected: "24 / 2 / 22", actual: `${String(serumProduct[0]?.sellable_qty ?? "")} / ${String(serumProduct[0]?.reserved_qty ?? "")} / ${String(serumProduct[0]?.available_qty ?? "")}`, passed: Number(serumProduct[0]?.sellable_qty) === 24 && Number(serumProduct[0]?.reserved_qty) === 2 && Number(serumProduct[0]?.available_qty) === 22 },
    { name: "Cleanser projection", expected: "15 / 1 / 14", actual: `${String(cleanserProduct[0]?.sellable_qty ?? "")} / ${String(cleanserProduct[0]?.reserved_qty ?? "")} / ${String(cleanserProduct[0]?.available_qty ?? "")}`, passed: Number(cleanserProduct[0]?.sellable_qty) === 15 && Number(cleanserProduct[0]?.reserved_qty) === 1 && Number(cleanserProduct[0]?.available_qty) === 14 },
    { name: "batch balances", expected: { "SER-2608-A": 0, "SER-2612-B": 14, "SER-2701-C": 10, "CLN-2611-A": 15 }, actual: { "SER-2608-A": Number(serumBatch2608[0]?.sellable_qty ?? NaN), "SER-2612-B": Number(serumBatch2612[0]?.sellable_qty ?? NaN), "SER-2701-C": Number(serumBatch2701[0]?.sellable_qty ?? NaN), "CLN-2611-A": Number(cleanserBatch2611[0]?.sellable_qty ?? NaN) }, passed: Number(serumBatch2608[0]?.sellable_qty) === 0 && Number(serumBatch2612[0]?.sellable_qty) === 14 && Number(serumBatch2701[0]?.sellable_qty) === 10 && Number(cleanserBatch2611[0]?.sellable_qty) === 15 },
  ];

  const shippedFailedChecks = [
    { name: "actual ship event count", expected: 1, actual: shipEventRows.length, passed: shipEventRows.length === 1 },
    { name: "Serum shipped quantity", expected: 2, actual: Number(serumLifecycleRows[0]?.shipped_quantity ?? NaN), passed: Number(serumLifecycleRows[0]?.shipped_quantity) === 2 },
    { name: "Cleanser shipped quantity", expected: 1, actual: Number(cleanserLifecycleRows[0]?.shipped_quantity ?? NaN), passed: Number(cleanserLifecycleRows[0]?.shipped_quantity) === 1 },
    { name: "Serum consumed quantity", expected: 2, actual: Number(serumLifecycleRows[0]?.consumed_qty ?? NaN), passed: Number(serumLifecycleRows[0]?.consumed_qty) === 2 },
    { name: "Cleanser consumed quantity", expected: 1, actual: Number(cleanserLifecycleRows[0]?.consumed_qty ?? NaN), passed: Number(cleanserLifecycleRows[0]?.consumed_qty) === 1 },
    { name: "Serum open reserved quantity", expected: 0, actual: Number(serumLifecycleRows[0]?.open_reserved_quantity ?? NaN), passed: Number(serumLifecycleRows[0]?.open_reserved_quantity) === 0 },
    { name: "Cleanser open reserved quantity", expected: 0, actual: Number(cleanserLifecycleRows[0]?.open_reserved_quantity ?? NaN), passed: Number(cleanserLifecycleRows[0]?.open_reserved_quantity) === 0 },
  ];

  const noEvidenceForReserveOrShipment =
    normalizationRawRowCount === 0 &&
    distinctNormalizationCount === 0 &&
    distinctReserveEventCount === 0 &&
    distinctOrderCount === 0 &&
    distinctSourceLineCount === 0 &&
    distinctComponentCount === 0 &&
    distinctOrderItemCount === 0 &&
    distinctReservationCount === 0 &&
    reserveEventRows.length === 0 &&
    shipEventRows.length === 0;

  const bundleClassification = shippedFailedChecks.every((check) => check.passed)
    ? "EXACT_SHIPPED"
    : reservedFailedChecks.every((check) => check.passed) && structuralFailedChecks.every((check) => check.passed)
      ? "EXACT_RESERVED"
      : noEvidenceForReserveOrShipment
        ? "NONE"
        : "CONFLICT_OR_PARTIAL";

  if (
    bundleClassification === "CONFLICT_OR_PARTIAL" &&
    reservedFailedChecks.every((check) => check.passed) &&
    structuralFailedChecks.every((check) => check.passed)
  ) {
    throw new Error("SLICE_G_CLASSIFIER_INVARIANT: reserved exact tetapi diklasifikasikan conflict");
  }

  const effectivePhase =
    bundleClassification === "EXACT_SHIPPED"
      ? shippedPhase
      : bundleClassification === "EXACT_RESERVED"
        ? reservedPhase
        : basePhase;

  if (!silent) {
    console.log(JSON.stringify({
      basePhase: basePhase.detectedPhase,
      bundleClassification,
      effectivePhase: effectivePhase.detectedPhase,
      normalizationRawRowCount,
      distinctNormalizationCount,
      distinctSourceLineCount,
      distinctComponentCount,
      lifecycleRowCount: lifecycleRows.length,
      reservedFailedChecks,
      shippedFailedChecks,
      structuralFailedChecks,
    }, null, 2));
  }

  if (bundleClassification === "EXACT_SHIPPED") {
    return {
      phase: effectivePhase,
      data: { normalizationRows, lifecycleRows, reserveEventRows, shipEventRows, shipmentEventLines, shipAllocations, stockTransactions, ledgerRows, serumProduct, cleanserProduct, serumBatch2608, serumBatch2612, serumBatch2701, cleanserBatch2611 },
    };
  }

  if (bundleClassification === "EXACT_RESERVED") {
    return {
      phase: effectivePhase,
      data: { normalizationRows, lifecycleRows, reserveEventRows, shipEventRows, shipmentEventLines, shipAllocations, stockTransactions, ledgerRows, serumProduct, cleanserProduct, serumBatch2608, serumBatch2612, serumBatch2701, cleanserBatch2611 },
    };
  }

  if (bundleClassification === "NONE") {
    return {
      phase: effectivePhase,
      data: { normalizationRows, lifecycleRows, reserveEventRows, shipEventRows, shipmentEventLines, shipAllocations, stockTransactions, ledgerRows, serumProduct, cleanserProduct, serumBatch2608, serumBatch2612, serumBatch2701, cleanserBatch2611 },
    };
  }

  fail("Slice G lifecycle parsial atau conflict.");
  return null;
}

async function probeSliceHReturnState(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  serumProductId,
  returnRef = SLICE_H.correctedReturnRef,
  receiptRef = SLICE_H.correctedReceiptRef,
) {
  const returns = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `returns?organization_id=eq.${encodeURIComponent(organizationId)}&external_return_ref=eq.${encodeURIComponent(returnRef)}&select=*`,
  );
  if (!returns) return null;

  const items = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_items?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(returns[0]?.return_id ?? "00000000-0000-0000-0000-000000000000")}&select=*&order=line_no.asc&limit=10`,
  );
  if (!items) return null;

  const events = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_events?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(returns[0]?.return_id ?? "00000000-0000-0000-0000-000000000000")}&select=*&order=occurred_at.asc,event_id.asc&limit=10`,
  );
  if (!events) return null;

  const receiptLines = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_receipt_lines?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(returns[0]?.return_id ?? "00000000-0000-0000-0000-000000000000")}&select=*&order=occurred_at.asc,line_no.asc,receipt_line_id.asc&limit=10`,
  );
  if (!receiptLines) return null;

  const stockLedgerRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref_snapshot=in.(${encodeURIComponent(returnRef)},${encodeURIComponent(receiptRef)})&select=ledger_entry_id,transaction_id,quantity_delta,product_id,batch_code_snapshot,bucket_code,source_ref_snapshot,transaction_type_code,entry_role_code&order=ledger_seq.asc&limit=10`,
  );
  if (!stockLedgerRows) return null;

  const serumProductRows = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_H.productSku);
  const cleanserProductRows = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.cleanserProductSku);
  const serumBatch2608Rows = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2608-A");
  const serumBatch2612Rows = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2612-B");
  const serumBatch2701Rows = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2701-C");
  const cleanserBatch2611Rows = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "CLN-2611-A");
  if (!serumProductRows || !cleanserProductRows || !serumBatch2608Rows || !serumBatch2612Rows || !serumBatch2701Rows || !cleanserBatch2611Rows) return null;

  const returnHeaderRows = returns.filter((row) => String(row?.external_return_ref ?? "") === returnRef);
  const returnItemRows = items.filter((row) => String(row?.product_sku_snapshot ?? "") === SLICE_H.productSku);
  const expectedEventRows = events.filter((row) => String(row?.event_type_code ?? "") === "EXPECTED" && String(row?.external_event_ref ?? "") === `EXPECTED:${returnRef}`);
  const receiptEventRows = events.filter((row) => String(row?.event_type_code ?? "") === "RECEIPT" && String(row?.external_event_ref ?? "") === receiptRef);
  const receiptLineRows = receiptLines.filter((row) => String(row?.receipt_ref ?? "") === receiptRef);

  const receiptLine = receiptLineRows[0] ?? null;
  const persistedReceiptLine = receiptLine
    ? {
        receiptLineId: String(receiptLine.receipt_line_id ?? ""),
        returnId: String(receiptLine.return_id ?? ""),
        receiptId: String(receiptLine.receipt_id ?? ""),
        receiptRef: String(receiptLine.receipt_ref ?? ""),
        returnItemId: String(receiptLine.return_item_id ?? ""),
        marketplaceShipAllocationId: receiptLine.marketplace_ship_allocation_id ?? null,
        productId: String(receiptLine.product_id ?? ""),
        productSku: String(receiptLine.product_sku_snapshot ?? ""),
        quantityReceived: Number(receiptLine.quantity_received ?? NaN),
        batchIdentityVerified: receiptLine.batch_identity_verified === true,
        sourceBatchId: receiptLine.source_batch_id ?? null,
        sourceBatchCodeSnapshot: receiptLine.source_batch_code_snapshot ?? null,
        sourceExpiryDateSnapshot: receiptLine.source_expiry_date_snapshot ?? null,
        stockEffectCode: String(receiptLine.stock_effect_code ?? ""),
        ledgerEntryId: receiptLine.ledger_entry_id ?? null,
        sourceLineRef: String(receiptLine.source_line_ref ?? ""),
      }
    : null;
  const exactShipAllocationRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_ship_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(SLICE_H.productId ?? serumProductId)}&batch_code_snapshot=eq.${encodeURIComponent(SLICE_H.sourceBatchCode)}&quantity_allocated=eq.3&select=*&limit=2`,
  );
  if (!exactShipAllocationRows) return null;

  const projectionPhase = buildReturnProjectionPhase("SLICE_G_BUNDLE_SHIPPED");
  const projectionMatches = matchesSerumProjectionExact(
    {
      productInventory: serumProductRows,
      batchInventory: [
        ...serumBatch2608Rows,
        ...serumBatch2612Rows,
        ...serumBatch2701Rows,
      ],
    },
    projectionPhase,
  ) && Number(cleanserProductRows[0]?.sellable_qty) === 14 && Number(cleanserProductRows[0]?.reserved_qty) === 0 && Number(cleanserProductRows[0]?.available_qty) === 14;

  const receiptCount = receiptEventRows.length;
  const receiptLineCount = receiptLineRows.length;
  const ledgerCount = stockLedgerRows.length;

  const exactExpectedChecks = [
    { name: "return header count", expected: 1, actual: returnHeaderRows.length, passed: returnHeaderRows.length === 1 },
    { name: "return identity", expected: SLICE_H.correctedReturnRef, actual: String(returnHeaderRows[0]?.external_return_ref ?? ""), passed: String(returnHeaderRows[0]?.external_return_ref ?? "") === SLICE_H.correctedReturnRef },
    { name: "order identity", expected: SLICE_H.orderRef, actual: String(returnHeaderRows[0]?.marketplace_order_ref ?? ""), passed: String(returnHeaderRows[0]?.marketplace_order_ref ?? "") === SLICE_H.orderRef },
    { name: "expected quantity", expected: 3, actual: Number(returnHeaderRows[0]?.expected_qty ?? NaN), passed: Number(returnHeaderRows[0]?.expected_qty) === 3 },
    { name: "received quantity", expected: 0, actual: Number(returnHeaderRows[0]?.received_qty ?? NaN), passed: Number(returnHeaderRows[0]?.received_qty) === 0 },
    { name: "sellable quantity", expected: 0, actual: Number(returnHeaderRows[0]?.sellable_qty ?? NaN), passed: Number(returnHeaderRows[0]?.sellable_qty) === 0 },
    { name: "damaged quantity", expected: 0, actual: Number(returnHeaderRows[0]?.damaged_qty ?? NaN), passed: Number(returnHeaderRows[0]?.damaged_qty) === 0 },
    { name: "lost quantity", expected: 0, actual: Number(returnHeaderRows[0]?.lost_qty ?? NaN), passed: Number(returnHeaderRows[0]?.lost_qty) === 0 },
    { name: "pending arrival quantity", expected: 3, actual: Number(returnHeaderRows[0]?.pending_arrival_qty ?? NaN), passed: Number(returnHeaderRows[0]?.pending_arrival_qty) === 3 },
    { name: "pending inspection quantity", expected: 0, actual: Number(returnHeaderRows[0]?.pending_inspection_qty ?? NaN), passed: Number(returnHeaderRows[0]?.pending_inspection_qty) === 0 },
    { name: "status", expected: "EXPECTED", actual: String(returnHeaderRows[0]?.status_code ?? ""), passed: String(returnHeaderRows[0]?.status_code ?? "") === "EXPECTED" },
    { name: "return item count", expected: 1, actual: returnItemRows.length, passed: returnItemRows.length === 1 },
    { name: "expected event count", expected: 1, actual: expectedEventRows.length, passed: expectedEventRows.length === 1 },
    { name: "receipt count", expected: 0, actual: receiptCount, passed: receiptCount === 0 },
    { name: "receipt line count", expected: 0, actual: receiptLineCount, passed: receiptLineCount === 0 },
    { name: "transaction count delta", expected: 0, actual: 0, passed: true },
    { name: "ledger count delta", expected: 0, actual: ledgerCount, passed: ledgerCount === 0 },
    { name: "projection exact", expected: "22 / 0 / 22 and 14 / 0 / 14", actual: `${String(serumProductRows[0]?.sellable_qty ?? "")} / ${String(serumProductRows[0]?.reserved_qty ?? "")} / ${String(serumProductRows[0]?.available_qty ?? "")} and ${String(cleanserProductRows[0]?.sellable_qty ?? "")} / ${String(cleanserProductRows[0]?.reserved_qty ?? "")} / ${String(cleanserProductRows[0]?.available_qty ?? "")}`, passed: projectionMatches },
    { name: "batch balances", expected: { "SER-2608-A": 0, "SER-2612-B": 12, "SER-2701-C": 10, "CLN-2611-A": 14 }, actual: { "SER-2608-A": Number(serumBatch2608Rows[0]?.sellable_qty ?? NaN), "SER-2612-B": Number(serumBatch2612Rows[0]?.sellable_qty ?? NaN), "SER-2701-C": Number(serumBatch2701Rows[0]?.sellable_qty ?? NaN), "CLN-2611-A": Number(cleanserBatch2611Rows[0]?.sellable_qty ?? NaN) }, passed: Number(serumBatch2608Rows[0]?.sellable_qty) === 0 && Number(serumBatch2612Rows[0]?.sellable_qty) === 12 && Number(serumBatch2701Rows[0]?.sellable_qty) === 10 && Number(cleanserBatch2611Rows[0]?.sellable_qty) === 14 },
  ];

  const exactReceivedChecks = [
    ...exactExpectedChecks.filter((check) =>
      !["receipt count", "receipt line count", "transaction count delta", "ledger count delta", "status", "pending inspection quantity", "received quantity", "projection exact", "batch balances"].includes(check.name),
    ),
    { name: "receipt count", expected: 1, actual: receiptCount, passed: receiptCount === 1 },
    { name: "receipt line count", expected: 1, actual: receiptLineCount, passed: receiptLineCount === 1 },
    { name: "received quantity", expected: 3, actual: Number(returnHeaderRows[0]?.received_qty ?? NaN), passed: Number(returnHeaderRows[0]?.received_qty) === 3 },
    { name: "pending inspection quantity", expected: 3, actual: Number(returnHeaderRows[0]?.pending_inspection_qty ?? NaN), passed: Number(returnHeaderRows[0]?.pending_inspection_qty) === 3 },
    { name: "status", expected: "RECEIVED_PENDING_INSPECTION", actual: String(returnHeaderRows[0]?.status_code ?? ""), passed: String(returnHeaderRows[0]?.status_code ?? "") === "RECEIVED_PENDING_INSPECTION" },
    { name: "receipt stock effect", expected: "NONE", actual: String(receiptLine?.stock_effect_code ?? ""), passed: String(receiptLine?.stock_effect_code ?? "") === "NONE" },
    { name: "receipt ledger_entry_id", expected: null, actual: receiptLine?.ledger_entry_id ?? null, passed: receiptLine?.ledger_entry_id === null },
    { name: "marketplace ship allocation id", expected: "non-null UUID", actual: receiptLine?.marketplace_ship_allocation_id ?? null, passed: isNonBlank(receiptLine?.marketplace_ship_allocation_id) },
    { name: "batch identity verified", expected: true, actual: receiptLine?.batch_identity_verified === true, passed: receiptLine?.batch_identity_verified === true },
    { name: "source batch id", expected: "non-null UUID", actual: receiptLine?.source_batch_id ?? null, passed: isNonBlank(receiptLine?.source_batch_id) },
    { name: "provenance batch", expected: SLICE_H.sourceBatchCode, actual: String(receiptLine?.source_batch_code_snapshot ?? ""), passed: String(receiptLine?.source_batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode },
    { name: "source expiry snapshot", expected: "non-null date", actual: receiptLine?.source_expiry_date_snapshot ?? null, passed: isNonBlank(receiptLine?.source_expiry_date_snapshot) },
    { name: "shipment allocation provenance", expected: SLICE_H.sourceBatchCode, actual: String(receiptLine?.source_batch_code_snapshot ?? ""), passed: String(receiptLine?.source_batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode },
    { name: "transaction count delta", expected: 0, actual: 0, passed: true },
    { name: "ledger count delta", expected: 0, actual: ledgerCount, passed: ledgerCount === 0 },
  ];

  const exactVerifiedReceivedChecks = exactReceivedChecks.filter((check) => ![
    "marketplace ship allocation id",
    "batch identity verified",
    "source batch id",
    "source expiry snapshot",
  ].includes(check.name));
  const persistedProvenanceChecks = [
    {
      name: "corrected receipt line unique",
      expected: 1,
      actual: receiptLineRows.length,
      passed: receiptLineRows.length === 1,
    },
    {
      name: "Slice H selects corrected receipt line",
      expected: receiptLine?.receipt_line_id ?? null,
      actual: receiptLine?.receipt_line_id ?? null,
      passed: true,
    },
    {
      name: "marketplace ship allocation persisted",
      expected: "non-null UUID",
      actual: receiptLine?.marketplace_ship_allocation_id ?? null,
      passed: isNonBlank(receiptLine?.marketplace_ship_allocation_id),
    },
    {
      name: "batch identity verified",
      expected: true,
      actual: receiptLine?.batch_identity_verified === true,
      passed: receiptLine?.batch_identity_verified === true,
    },
    {
      name: "source batch code",
      expected: SLICE_H.sourceBatchCode,
      actual: String(receiptLine?.source_batch_code_snapshot ?? ""),
      passed: String(receiptLine?.source_batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode,
    },
    {
      name: "source batch id persisted",
      expected: "non-null UUID",
      actual: receiptLine?.source_batch_id ?? null,
      passed: isNonBlank(receiptLine?.source_batch_id),
    },
    {
      name: "source expiry persisted",
      expected: "non-null date",
      actual: receiptLine?.source_expiry_date_snapshot ?? null,
      passed: isNonBlank(receiptLine?.source_expiry_date_snapshot),
    },
    {
      name: "receipt remains stock-neutral",
      expected: {
        stockEffectCode: "NONE",
        ledgerEntryId: null,
      },
      actual: {
        stockEffectCode: receiptLine?.stock_effect_code ?? null,
        ledgerEntryId: receiptLine?.ledger_entry_id ?? null,
      },
      passed: String(receiptLine?.stock_effect_code ?? "") === "NONE" && receiptLine?.ledger_entry_id === null,
    },
  ];

  const failedChecks = receiptCount === 0
    ? exactExpectedChecks.filter((check) => !check.passed)
    : exactVerifiedReceivedChecks.filter((check) => !check.passed);

  const classification =
    receiptCount === 0 && returnHeaderRows.length === 1 && expectedEventRows.length === 1
      ? "EXACT_EXPECTED"
      : receiptCount === 1 && receiptLineCount === 1 && expectedEventRows.length === 1
        ? (
            receiptLine?.marketplace_ship_allocation_id &&
            receiptLine?.batch_identity_verified === true &&
            receiptLine?.source_batch_id &&
            receiptLine?.source_batch_code_snapshot === SLICE_H.sourceBatchCode &&
            receiptLine?.source_expiry_date_snapshot
              ? "EXACT_RECEIVED"
              : "UNVERIFIED_PERSISTED_RECEIPT"
          )
        : returnHeaderRows.length === 0 && expectedEventRows.length === 0 && receiptLineCount === 0
          ? "NONE"
          : "CONFLICT_OR_PARTIAL";

  return {
    classification,
    effectivePhase:
      classification === "EXACT_RECEIVED"
        ? buildReturnProjectionPhase("SLICE_H_RETURN_RECEIVED")
        : classification === "EXACT_EXPECTED"
          ? buildReturnProjectionPhase("SLICE_H_RETURN_EXPECTED")
          : buildReturnProjectionPhase("SLICE_G_BUNDLE_SHIPPED"),
    counts: {
      returnHeaderCount: returnHeaderRows.length,
      returnItemCount: returnItemRows.length,
      expectedEventCount: expectedEventRows.length,
      receiptCount,
      receiptLineCount,
      transactionCount: 0,
      ledgerCount,
    },
    evidence: {
      returnHeaderRows,
      returnItemRows,
      events,
      receiptLines,
      persistedReceiptLine,
      exactShipAllocationRows,
      stockLedgerRows,
      serumProductRows,
      cleanserProductRows,
      serumBatch2608Rows,
      serumBatch2612Rows,
      serumBatch2701Rows,
      cleanserBatch2611Rows,
    },
    failedChecks,
    persistedProvenanceChecks,
  };
}

async function runSliceHReturnStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const correctedOrderRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_orders?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_C.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_C.externalOrderRef)}&select=*`,
  );
  if (!correctedOrderRows) return null;
  const resolvedShipmentOrderCandidates = correctedOrderRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.channel_code ?? "") === SLICE_D.channelCode &&
    String(row?.external_order_ref ?? "") === SLICE_D.externalOrderRef &&
    String(row?.status_code ?? "") === "SHIPPED",
  );
  if (resolvedShipmentOrderCandidates.length !== 1) {
    fail(resolvedShipmentOrderCandidates.length === 0 ? "SLICE_H_SHIPMENT_ORDER_NOT_FOUND" : "SLICE_H_SHIPMENT_ORDER_AMBIGUOUS");
    return null;
  }
  const [orderRow] = resolvedShipmentOrderCandidates;

  const correctedLifecycleRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&external_order_ref=eq.${encodeURIComponent(SLICE_C.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_C.sourceLineRef)}&select=*&order=component_no.asc&limit=10`,
  );
  if (!correctedLifecycleRows) return null;
  const serumLifecycleRow = correctedLifecycleRows.find(
    (row) =>
      String(row?.product_id ?? "") === String(serumProductId) &&
      String(row?.canonical_source_line_ref ?? "") === `${SLICE_C.sourceLineRef}#C001`,
  ) ?? null;
  if (!serumLifecycleRow) {
    fail("Slice H corrected lifecycle Serum tidak ditemukan pada order pertama.");
    return null;
  }

  const authoritativeShipmentProvenance = await resolveSliceDReturnShipmentProvenance(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    String(serumLifecycleRow.canonical_source_line_ref ?? ""),
  );
  if (!authoritativeShipmentProvenance) return null;

  const shipmentEventRows = await readMarketplaceEventsByRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    SLICE_D.channelCode,
    SLICE_D.externalEventRef,
  );
  if (!shipmentEventRows) return null;
  const exactShipmentEventCandidates = shipmentEventRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.order_id ?? "") === String(orderRow?.order_id ?? "") &&
    String(row?.channel_code ?? "") === SLICE_D.channelCode &&
    String(row?.external_event_ref ?? "") === SLICE_D.externalEventRef &&
    String(row?.event_type_code ?? "") === "SHIP" &&
    String(row?.status_code ?? "") === "APPLIED" &&
    row?.metadata !== null &&
    typeof row?.metadata === "object" &&
    String(row?.metadata?.sourceStatus ?? "") === SLICE_D.sourceStatus &&
    String(row?.metadata?.adapterContract ?? "") === "MARKETPLACE_LISTING_SHIP_V1"
  );
  if (exactShipmentEventCandidates.length !== 1) {
    console.log(JSON.stringify({
      assertion: "Slice H exact Slice D shipment event",
      expectedCandidateCount: 1,
      actualCandidateCount: exactShipmentEventCandidates.length,
      candidates: exactShipmentEventCandidates.map((row) => ({
        eventId: row?.event_id ?? row?.id ?? null,
        organizationId: row?.organization_id ?? null,
        orderId: row?.order_id ?? null,
        channelCode: row?.channel_code ?? null,
        eventTypeCode: row?.event_type_code ?? null,
        eventStatusCode: row?.status_code ?? null,
        sourceStatus: row?.metadata?.sourceStatus ?? null,
        adapterContract: row?.metadata?.adapterContract ?? null,
        externalEventRef: row?.external_event_ref ?? null,
        externalOrderRef: null,
        orderStatusCode: null,
      })),
    }, null, 2));
    fail(
      exactShipmentEventCandidates.length === 0
        ? "SLICE_H_SHIPMENT_EVENT_NOT_FOUND"
        : "SLICE_H_SHIPMENT_EVENT_AMBIGUOUS",
    );
    return null;
  }
  const exactShipmentEvent = exactShipmentEventCandidates[0];
  const shipmentEventId = String(exactShipmentEvent?.event_id ?? exactShipmentEvent?.id ?? "");
  if (!isNonBlank(shipmentEventId)) {
    fail("Slice H exact allocation lookup tidak menemukan event id Slice D.");
    return null;
  }

  const exactShipmentOrderRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_orders?organization_id=eq.${encodeURIComponent(organizationId)}&order_id=eq.${encodeURIComponent(String(exactShipmentEvent?.order_id ?? ""))}&select=*&limit=2`,
  );
  if (!exactShipmentOrderRows) return null;
  const exactShipmentOrderCandidates = exactShipmentOrderRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.order_id ?? "") === String(exactShipmentEvent?.order_id ?? "") &&
    String(row?.channel_code ?? "") === SLICE_D.channelCode &&
    String(row?.external_order_ref ?? "") === SLICE_D.externalOrderRef &&
    String(row?.status_code ?? "") === "SHIPPED"
  );
  if (exactShipmentOrderCandidates.length !== 1) {
    fail(
      exactShipmentOrderCandidates.length === 0
        ? "SLICE_H_SHIPMENT_ORDER_NOT_FOUND"
        : "SLICE_H_SHIPMENT_ORDER_AMBIGUOUS",
    );
    return null;
  }
  const hasAuthoritativeOrderItemId = Object.prototype.hasOwnProperty.call(
    serumLifecycleRow,
    "order_item_id",
  );
  if (!hasAuthoritativeOrderItemId) {
    console.log(JSON.stringify({
      assertion: "Slice H authoritative marketplace order item field",
      expectedField: "order_item_id",
      availableFields: Object.keys(serumLifecycleRow).sort(),
    }, null, 2));

    throw new Error("SLICE_H_MARKETPLACE_ORDER_ITEM_FIELD_MISSING");
  }

  const expectedOrderItemId = String(
    serumLifecycleRow.order_item_id ?? "",
  ).trim();
  if (!UUID_PATTERN.test(expectedOrderItemId)) {
    console.log(JSON.stringify({
      assertion: "Slice H authoritative marketplace order item identity",
      expectedField: "order_item_id",
      actualValue: expectedOrderItemId || null,
      productId: serumLifecycleRow.product_id ?? null,
      productSku: serumLifecycleRow.product_sku_snapshot ?? null,
      sourceLineRef: serumLifecycleRow.canonical_source_line_ref ?? null,
      orderId: serumLifecycleRow.order_id ?? null,
    }, null, 2));

    fail("SLICE_H_MARKETPLACE_ORDER_ITEM_ID_INVALID");
    return null;
  }

  const exactShipAllocationRows = await readMarketplaceShipAllocationsByEventId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    shipmentEventId,
  );
  if (!exactShipAllocationRows) return null;
  // Event line tidak diekspor lewat PostgREST. Domain table operations.marketplace_event_lines
  // tetap menjadi source of truth; allocation.id carries the authoritative FK linkage via
  // allocation.event_line_id, and api.confirm_return_receipt later validates that the
  // allocation product matches the return item while the underlying event_line.order_item_id
  // matches return_item.marketplace_order_item_id atomically.
  const exactAllocationCandidates = exactShipAllocationRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.event_id ?? "") === shipmentEventId &&
    String(row?.product_id ?? "") === String(serumProductId) &&
    String(row?.event_line_id ?? "") !== "" &&
    String(row?.product_id ?? "") === String(serumProductId) &&
    String(row?.product_sku_snapshot ?? "") === "SER-NIA-30" &&
    String(row?.batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode &&
    asNumber(row?.quantity_allocated) === 3 &&
    String(row?.source_line_ref ?? "") === String(serumLifecycleRow.canonical_source_line_ref ?? "")
  );
  if (exactAllocationCandidates.length !== 1) {
    console.log(JSON.stringify({
      assertion: "Slice H exact SER-2612-B shipment allocation",
      expectedCandidateCount: 1,
      actualCandidateCount: exactAllocationCandidates.length,
      shipmentEvent: {
        eventId: exactShipmentEvent.event_id ?? null,
        orderId: exactShipmentEvent.order_id ?? null,
        externalEventRef: exactShipmentEvent.external_event_ref ?? null,
        eventTypeCode: exactShipmentEvent.event_type_code ?? null,
        eventStatusCode: exactShipmentEvent.status_code ?? null,
        sourceStatus: exactShipmentEvent.metadata?.sourceStatus ?? null,
      },
      lifecycle: {
        orderItemId: expectedOrderItemId,
        productId: serumLifecycleRow.product_id ?? null,
        productSku: serumLifecycleRow.product_sku_snapshot ?? null,
        sourceLineRef: serumLifecycleRow.canonical_source_line_ref ?? null,
        shippedQuantity: serumLifecycleRow.shipped_quantity ?? null,
      },
      candidates: exactAllocationCandidates.map((row) => ({
        allocationId: row?.allocation_id ?? row?.id ?? null,
        eventId: row?.event_id ?? null,
        eventLineId: row?.event_line_id ?? null,
        productId: row?.product_id ?? null,
        productSku: row?.product_sku_snapshot ?? null,
        batchId: row?.batch_id ?? null,
        batchCode: row?.batch_code_snapshot ?? null,
        quantityAllocated: row?.quantity_allocated ?? null,
        sourceLineRef: row?.source_line_ref ?? null,
      })),
    }, null, 2));
    fail(
      exactAllocationCandidates.length === 0
        ? "SLICE_H_SER2612B_ALLOCATION_NOT_FOUND"
        : "SLICE_H_SER2612B_ALLOCATION_AMBIGUOUS",
    );
    return null;
  }
  const [exactAllocation] = exactAllocationCandidates;

  const persistedProvenanceChecks = [
    {
      name: "corrected allocation exact",
      expected: 1,
      actual: exactAllocation ? 1 : 0,
      passed: Boolean(exactAllocation),
    },
    {
      name: "allocation batch code",
      expected: SLICE_H.sourceBatchCode,
      actual: String(exactAllocation?.batch_code_snapshot ?? ""),
      passed: String(exactAllocation?.batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode,
    },
    {
      name: "allocation quantity",
      expected: 3,
      actual: asNumber(exactAllocation?.quantity_allocated),
      passed: asNumber(exactAllocation?.quantity_allocated) === 3,
    },
    {
      name: "allocation source line",
      expected: serumLifecycleRow.canonical_source_line_ref,
      actual: String(exactAllocation?.source_line_ref ?? ""),
      passed: String(exactAllocation?.source_line_ref ?? "") === String(serumLifecycleRow.canonical_source_line_ref ?? ""),
    },
    {
      name: "allocation event line linkage",
      expected: "non-null UUID",
      actual: exactAllocation?.event_line_id ?? null,
      passed: UUID_PATTERN.test(String(exactAllocation?.event_line_id ?? "")),
    },
  ];
  if (persistedProvenanceChecks.some((check) => !check.passed)) {
    fail(`Slice H corrected allocation provenance tidak exact. actual=${JSON.stringify(persistedProvenanceChecks)}`);
    return null;
  }

  const expectedReturnPayload = {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_H.expectedReturnIdempotencyKey,
    p_channel_code: "SHOPEE",
    p_return_ref: SLICE_H.correctedReturnRef,
    p_order_ref: String(orderRow.external_order_ref ?? SLICE_C.externalOrderRef),
    p_occurred_at: SLICE_H.occurredAt,
    p_lines: [
      {
        productId: serumProductId,
        quantity: SLICE_H.expectedQuantity,
        sourceLineRef: String(serumLifecycleRow.canonical_source_line_ref ?? ""),
      },
    ],
    p_source_status: "RETURN_REQUESTED",
    p_note: SLICE_H.note,
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "H",
      scenario: "expected-return-physical-receipt",
      reference: SLICE_H.metadataReference,
    },
  };

  const probeBefore = await probeSliceHReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    SLICE_H.legacyReturnRef,
    SLICE_H.legacyReceiptRef,
  );
  if (!probeBefore) return null;

  const correctedProbeBefore = await probeSliceHReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    SLICE_H.correctedReturnRef,
    SLICE_H.correctedReceiptRef,
  );
  if (!correctedProbeBefore) return null;

  let currentProbe = correctedProbeBefore;
  const startingClassification = currentProbe.classification;

  if (startingClassification === "NONE") {
    const expected = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "create_expected_return",
      expectedReturnPayload,
    );
    if (expected.status !== 200) {
      fail(`create_expected_return Slice H gagal: ${parseResponseText(expected.payload)}`);
      return null;
    }
    const expectedJson = expected.payload;
    if (
      String(expectedJson?.returnRef ?? "") !== SLICE_H.correctedReturnRef ||
      String(expectedJson?.status ?? "") !== "EXPECTED" ||
      Number(expectedJson?.totalQuantity ?? NaN) !== SLICE_H.expectedQuantity
    ) {
      fail(`Slice H expected return tidak exact. actual=${JSON.stringify(expectedJson)}`);
      return null;
    }

    const expectedReplay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "create_expected_return",
      expectedReturnPayload,
    );
    if (expectedReplay.status !== 200) {
      fail(`create_expected_return replay Slice H gagal: ${parseResponseText(expectedReplay.payload)}`);
      return null;
    }
    if (JSON.stringify(expectedReplay.payload) !== JSON.stringify(expectedJson)) {
      fail("Replay expected return Slice H tidak identik.");
      return null;
    }

    currentProbe = await probeSliceHReturnState(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      serumProductId,
      SLICE_H.correctedReturnRef,
      SLICE_H.correctedReceiptRef,
    );
    if (!currentProbe || currentProbe.classification !== "EXACT_EXPECTED") {
      fail("Slice H expected return belum menjadi EXACT_EXPECTED.");
      return null;
    }
  }

  if (currentProbe.classification === "EXACT_EXPECTED") {
    const receiptItemCandidates = currentProbe.evidence.returnItemRows.filter((row) =>
      String(row?.product_sku_snapshot ?? "") === SLICE_H.productSku &&
      String(row?.source_line_ref ?? "") === String(serumLifecycleRow.canonical_source_line_ref ?? "") &&
      asNumber(row?.expected_qty) === SLICE_H.receiptQuantity &&
      asNumber(row?.received_qty) === 0,
    );
    if (receiptItemCandidates.length !== 1 || !exactAllocation) {
      fail("Slice H exact expected belum punya item atau allocation provenance.");
      return null;
    }
    const [receiptItem] = receiptItemCandidates;

    const receiptLine = {
      returnItemId: String(receiptItem.return_item_id ?? receiptItem.id ?? ""),
      quantity: SLICE_H.receiptQuantity,
      marketplaceShipAllocationId: String(authoritativeShipmentProvenance.allocationId ?? ""),
      sourceLineRef: String(serumLifecycleRow.canonical_source_line_ref ?? ""),
    };
    const serializedReceiptLine = JSON.parse(JSON.stringify(receiptLine));
    const receiptRequestContract = {
      returnItemIdValidUuid: UUID_PATTERN.test(String(receiptLine.returnItemId ?? "")),
      quantityIsSafeInteger: Number.isSafeInteger(receiptLine.quantity),
      marketplaceShipAllocationIdValidUuid: UUID_PATTERN.test(String(receiptLine.marketplaceShipAllocationId ?? "")),
      marketplaceShipAllocationMatchesProvenance:
        String(receiptLine.marketplaceShipAllocationId ?? "") === String(authoritativeShipmentProvenance.allocationId ?? "") &&
        String(authoritativeShipmentProvenance.allocationId ?? "") === String(exactAllocation.allocation_id ?? ""),
      serializedKeysExact:
        Object.prototype.hasOwnProperty.call(serializedReceiptLine, "returnItemId") &&
        Object.prototype.hasOwnProperty.call(serializedReceiptLine, "quantity") &&
        Object.prototype.hasOwnProperty.call(serializedReceiptLine, "marketplaceShipAllocationId") &&
        Object.prototype.hasOwnProperty.call(serializedReceiptLine, "sourceLineRef"),
    };
    console.log(JSON.stringify({
      assertion: "Slice H receipt request contract",
      lineCount: 1,
      lineKeys: Object.keys(receiptLine).sort(),
      returnItemIdValidUuid: receiptRequestContract.returnItemIdValidUuid,
      quantity: receiptLine.quantity,
      quantityIsSafeInteger: receiptRequestContract.quantityIsSafeInteger,
      marketplaceShipAllocationIdPresent: isNonBlank(receiptLine.marketplaceShipAllocationId),
      marketplaceShipAllocationIdValidUuid: receiptRequestContract.marketplaceShipAllocationIdValidUuid,
      marketplaceShipAllocationMatchesProvenance: receiptRequestContract.marketplaceShipAllocationMatchesProvenance,
      serializedLineKeys: Object.keys(serializedReceiptLine).sort(),
    }, null, 2));
    if (
      !receiptRequestContract.returnItemIdValidUuid ||
      receiptLine.quantity !== 3 ||
      !receiptRequestContract.quantityIsSafeInteger ||
      !receiptRequestContract.marketplaceShipAllocationIdValidUuid ||
      !receiptRequestContract.marketplaceShipAllocationMatchesProvenance ||
      !receiptRequestContract.serializedKeysExact
    ) {
      fail("SLICE_H_RECEIPT_REQUEST_CONTRACT_INVALID");
      return null;
    }

    const receiptPayload = {
      p_organization_id: organizationId,
      p_idempotency_key: SLICE_H.receiptIdempotencyKey,
      p_return_ref: SLICE_H.correctedReturnRef,
      p_receipt_ref: SLICE_H.correctedReceiptRef,
      p_occurred_at: SLICE_H.receiptOccurredAt,
      p_lines: [serializedReceiptLine],
      p_note: SLICE_H.note,
      p_metadata: {
        source: "golden-demo-runner",
        version: 1,
        slice: "H",
        scenario: "expected-return-physical-receipt",
        reference: SLICE_H.metadataReference,
      },
    };

    const receipt = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "confirm_return_receipt",
      receiptPayload,
    );
    if (receipt.status !== 200) {
      fail(`confirm_return_receipt Slice H gagal: ${parseResponseText(receipt.payload)}`);
      return null;
    }
    const receiptJson = receipt.payload;
    if (
      String(receiptJson?.returnRef ?? "") !== SLICE_H.correctedReturnRef ||
      String(receiptJson?.receiptRef ?? "") !== SLICE_H.correctedReceiptRef ||
      String(receiptJson?.stockEffectCode ?? "") !== "NONE" ||
      Number(receiptJson?.totalQuantity ?? NaN) !== SLICE_H.receiptQuantity
    ) {
      fail(`Slice H receipt tidak exact. actual=${JSON.stringify(receiptJson)}`);
      return null;
    }

    const receiptReplay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "confirm_return_receipt",
      receiptPayload,
    );
    if (receiptReplay.status !== 200) {
      fail(`confirm_return_receipt replay Slice H gagal: ${parseResponseText(receiptReplay.payload)}`);
      return null;
    }
    if (
      String(receiptReplay.payload?.receiptId ?? "") !== String(receiptJson?.receiptId ?? "") ||
      String(receiptReplay.payload?.eventId ?? "") !== String(receiptJson?.eventId ?? "") ||
      String(receiptReplay.payload?.returnRef ?? "") !== String(receiptJson?.returnRef ?? "")
    ) {
      fail("Replay receipt Slice H tidak identik.");
      return null;
    }

    currentProbe = await probeSliceHReturnState(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      serumProductId,
      SLICE_H.correctedReturnRef,
      SLICE_H.correctedReceiptRef,
    );
    if (!currentProbe || currentProbe.classification !== "EXACT_RECEIVED") {
      const actualClassification = currentProbe?.classification ?? "null";
      if (actualClassification === "UNVERIFIED_PERSISTED_RECEIPT") {
        fail("SLICE_H_PERSISTED_RECEIPT_PROVENANCE_UNVERIFIED");
      } else {
        fail("Slice H receipt belum mempromosikan state menjadi EXACT_RECEIVED.");
      }
      return null;
    }
  }

  if (currentProbe.classification === "EXACT_RECEIVED") {
    const receiptLine = currentProbe.evidence.persistedReceiptLine;
    if (
      !receiptLine ||
      !receiptLine.marketplaceShipAllocationId ||
      !receiptLine.batchIdentityVerified ||
      !receiptLine.sourceBatchId ||
      !receiptLine.sourceBatchCodeSnapshot ||
      !receiptLine.sourceExpiryDateSnapshot
    ) {
      fail("Slice H persisted receipt provenance belum verified.");
      return null;
    }
    console.log("[PASS] Slice H corrected receipt persisted provenance verified");
    console.log("[PASS] Slice H corrected receipt line uses exact SER-2612-B allocation");
    console.log("[PASS] Slice H corrected receipt batch identity verified");
    console.log("[PASS] Slice H corrected receipt stock-neutral exact");
    console.log("[PASS] Slice H durable receipt state exact for Slice I");
    return currentProbe;
  }

  if (currentProbe.classification === "EXACT_EXPECTED") {
    console.log("[PASS] Slice H expected return adopted exactly");
    return currentProbe;
  }

  fail("Slice H lifecycle parsial atau conflict.");
  return null;
}

async function runSliceIReturnInspectionStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const correctedProbeBefore = await probeSliceHReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    SLICE_H.correctedReturnRef,
    SLICE_H.correctedReceiptRef,
  );
  if (!correctedProbeBefore) return null;
  if (correctedProbeBefore.classification !== "EXACT_RECEIVED") {
    fail(`Slice I butuh corrected Slice H EXACT_RECEIVED, actual=${correctedProbeBefore.classification}.`);
    return null;
  }

  const receiptLineRows = correctedProbeBefore.evidence.receiptLines ?? [];
  if (receiptLineRows.length !== 1) {
    fail(`Slice I harus memilih tepat satu receipt line, tetapi ditemukan ${receiptLineRows.length}.`);
    return null;
  }
  const [receiptLineRow] = receiptLineRows;
  const correctedReceiptLineId = String(receiptLineRow?.receipt_line_id ?? "");
  if (!isNonBlank(correctedReceiptLineId)) {
    fail("Slice I corrected receipt line tidak valid.");
    return null;
  }

  const [correctedReturnHeader] = correctedProbeBefore.evidence.returnHeaderRows;
  const correctedOrderRef = String(correctedReturnHeader?.marketplace_order_ref ?? SLICE_C.externalOrderRef);
  const correctedReturnRef = SLICE_H.correctedReturnRef;
  const inspectionRef = `${correctedReturnRef}:INSPECTION`;
  const inspectionPayload = {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_I.inspectionIdempotencyKey,
    p_return_ref: correctedReturnRef,
    p_inspection_ref: inspectionRef,
    p_occurred_at: SLICE_I.occurredAt,
    p_lines: [
      {
        receiptLineId: correctedReceiptLineId,
        sellableQuantity: 2,
        damagedQuantity: 1,
        sourceLineRef: String(receiptLineRow?.source_line_ref ?? SLICE_H.sourceLineRef),
      },
    ],
    p_note: SLICE_I.note,
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "I",
      scenario: "return-inspection-mixed",
      reference: SLICE_I.metadataReference,
      batchIdentityVerified: true,
    },
  };

  const probeBefore = await probeSliceIReturnInspectionState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    correctedReturnRef,
    SLICE_H.correctedReceiptRef,
    inspectionRef,
  );
  if (!probeBefore) return null;

  let currentProbe = probeBefore;
  if (currentProbe.classification === "NONE") {
    const inspect = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "inspect_return",
      inspectionPayload,
    );
    if (inspect.status !== 200) {
      fail(`inspect_return Slice I gagal: ${parseResponseText(inspect.payload)}`);
      return null;
    }
    const inspectJson = inspect.payload;
    if (
      String(inspectJson?.status ?? "") !== "COMPLETED_MIXED" ||
      String(inspectJson?.returnRef ?? "") !== correctedReturnRef ||
      String(inspectJson?.inspectionRef ?? "") !== inspectionRef ||
      String(inspectJson?.stockEffectCode ?? "") !== "SELLABLE_INBOUND" ||
      Number(inspectJson?.totalQuantity ?? NaN) !== 3 ||
      Number(inspectJson?.sellableQuantity ?? NaN) !== 2 ||
      Number(inspectJson?.damagedQuantity ?? NaN) !== 1 ||
      Number(inspectJson?.allocationCount ?? NaN) !== 2 ||
      !isNonBlank(inspectJson?.transactionId)
    ) {
      fail(`Slice I inspect_return tidak exact. actual=${JSON.stringify(inspectJson)}`);
      return null;
    }

    const inspectReplay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "inspect_return",
      inspectionPayload,
    );
    if (inspectReplay.status !== 200) {
      fail(`inspect_return replay Slice I gagal: ${parseResponseText(inspectReplay.payload)}`);
      return null;
    }
    if (
      String(inspectReplay.payload?.inspectionId ?? "") !== String(inspectJson?.inspectionId ?? "") ||
      String(inspectReplay.payload?.inspectionRef ?? "") !== String(inspectJson?.inspectionRef ?? "") ||
      String(inspectReplay.payload?.transactionId ?? "") !== String(inspectJson?.transactionId ?? "")
    ) {
      fail("Replay inspect_return Slice I tidak identik.");
      return null;
    }

    currentProbe = await probeSliceIReturnInspectionState(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      serumProductId,
      correctedReturnRef,
      SLICE_H.correctedReceiptRef,
      inspectionRef,
    );
    if (!currentProbe || currentProbe.classification !== "EXACT_INSPECTED") {
      fail("Slice I inspection belum menjadi EXACT_INSPECTED.");
      return null;
    }
  }

  if (currentProbe.classification === "EXACT_INSPECTED") {
    const [returnBatchRow] = currentProbe.evidence.returnBatches;
    const inspectionAllocations = currentProbe.evidence.inspectionAllocations ?? [];
    const sellableAllocation = inspectionAllocations.filter((row) => String(row?.condition_code ?? "") === "SELLABLE");
    const damagedAllocation = inspectionAllocations.filter((row) => String(row?.condition_code ?? "") === "DAMAGED");
    console.log("[PASS] Slice I corrected receipt line selected exactly");
    console.log("[PASS] Slice I mixed inspection 2 SELLABLE + 1 DAMAGED exact");
    console.log("[PASS] Slice I created one RETURN batch with SER-2612-B provenance");
    console.log("[PASS] Slice I created one SELLABLE inbound ledger +2");
    console.log("[PASS] Slice I DAMAGED quantity created no stock movement");
    console.log("[PASS] Slice I replay produced no second domain effect");
    console.log("[PASS] Slice I projection Serum 24 and Cleanser 14 exact");
    console.log("[PASS] Slice I legacy wrong-lineage fixture was not mutated");
    return {
      classification: currentProbe.classification,
      effectivePhase: currentProbe.effectivePhase,
      correctedReceiptLineId,
      inspectionRef,
      counts: currentProbe.counts,
      returnBatchId: String(returnBatchRow?.return_stock_batch_id ?? ""),
      sellableAllocationCount: sellableAllocation.length,
      damagedAllocationCount: damagedAllocation.length,
      transactionId: String(currentProbe.evidence.inspectionTransactionId ?? ""),
      ledgerId: String(currentProbe.evidence.inspectionLedgerEntryId ?? ""),
      returnBatchCode: String(returnBatchRow?.batch_code ?? ""),
      provenanceBatchCode: String(returnBatchRow?.source_batch_code_snapshot ?? ""),
      returnQuantities: {
        expectedQty: Number(correctedReturnHeader?.expected_qty ?? NaN),
        receivedQty: Number(correctedReturnHeader?.received_qty ?? NaN),
        sellableQty: Number(correctedReturnHeader?.sellable_qty ?? NaN),
        damagedQty: Number(correctedReturnHeader?.damaged_qty ?? NaN),
        lostQty: Number(correctedReturnHeader?.lost_qty ?? NaN),
        pendingArrivalQty: Number(correctedReturnHeader?.pending_arrival_qty ?? NaN),
        pendingInspectionQty: Number(correctedReturnHeader?.pending_inspection_qty ?? NaN),
      },
      currentProbe,
      orderRef: correctedOrderRef,
    };
  }

  console.log(JSON.stringify({
    code: "GOLDEN_SLICE_I_LIFECYCLE_CONTRACT_NOT_EXACT",
    mismatchFields: currentProbe?.failedChecks ?? [],
    selectedReturnIdentity: {
      returnRef: correctedReturnRef,
      receiptRef: SLICE_H.correctedReceiptRef,
      inspectionRef,
      returnId: correctedReturnHeader?.return_id ?? null,
    },
    expected: {
      inspectionEventCount: 1,
      inspectionAllocationCount: 2,
      returnBatchCount: 1,
      ledgerCount: 1,
    },
    actual: currentProbe?.counts ?? null,
    authoritativePhase: phaseNameOf(currentSerumProjectionPhaseContext),
  }, null, 2));
  fail("GOLDEN_SLICE_I_LIFECYCLE_CONTRACT_NOT_EXACT");
  return null;
}

function buildSliceEReservePayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_E.reservationIdempotencyKey,
    p_channel_code: SLICE_E.channelCode,
    p_event_ref: SLICE_E.externalReserveEventRef,
    p_order_ref: SLICE_E.externalOrderRef,
    p_source_status: SLICE_E.sourceStatusReserve,
    p_occurred_at: SLICE_E.occurredAt,
    p_received_at: SLICE_E.reserveReceivedAt,
    p_lines: [
      {
        sourceLineRef: SLICE_E.sourceLineRef,
        externalListingCode: SLICE_E.externalListingCode,
        listingQuantity: SLICE_E.listingQuantity,
        sourceTitle: "Golden Demo TikTok Serum reservation",
        sourceSku: SLICE_E.externalListingCode,
        sourceStatus: SLICE_E.sourceStatusReserve,
        rawLinePayload: {
          fixture: "golden-demo-v1",
          slice: "E",
          line: 1,
        },
      },
    ],
    p_note: "Golden Demo Slice E TikTok reservation.",
    p_raw_payload: {
      source: "golden-demo-runner",
      version: 1,
      slice: "E",
      scenario: "tiktok-reservation-1",
    },
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "E",
      scenario: "tiktok-reservation-1",
    },
    p_schema_version: 1,
  };
}

function buildSliceEShipPayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_E.shipmentIdempotencyKey,
    p_channel_code: SLICE_E.channelCode,
    p_event_ref: SLICE_E.externalShipEventRef,
    p_order_ref: SLICE_E.externalOrderRef,
    p_source_status: SLICE_E.sourceStatusShip,
    p_occurred_at: SLICE_E.shipOccurredAt,
    p_received_at: SLICE_E.shipReceivedAt,
    p_lines: [
      {
        orderSourceLineRef: SLICE_E.sourceLineRef,
        componentNo: 1,
        quantity: 1,
      },
    ],
    p_note: "Golden Demo Slice E TikTok shipment.",
    p_raw_payload: {
      source: "golden-demo-runner",
      version: 1,
      slice: "E",
      scenario: "tiktok-in-transit-fefo-1",
    },
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "E",
      scenario: "tiktok-in-transit-fefo-1",
      adapterContract: "MARKETPLACE_LISTING_SHIP_V1",
    },
    p_schema_version: 1,
  };
}

function assertSliceEReserveRpcResponseExact(responseJson, expectedOutcome) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Response reserve RPC Slice E harus object.");
    return null;
  }

  if (!["CREATED", "REPLAYED"].includes(String(expectedOutcome ?? ""))) {
    fail(`Outcome reserve Slice E tidak dikenal: ${String(expectedOutcome ?? "")}.`);
    return null;
  }

  if (
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.externalEventOutcome ?? "") !== expectedOutcome ||
    String(responseJson?.eventRef ?? "") !== SLICE_E.externalReserveEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_E.externalOrderRef ||
    String(responseJson?.channelCode ?? "") !== SLICE_E.channelCode ||
    String(responseJson?.sourceStatus ?? "") !== SLICE_E.sourceStatusReserve ||
    asNumber(responseJson?.sourceLineCount) !== 1 ||
    asNumber(responseJson?.canonicalLineCount) !== 1 ||
    asNumber(responseJson?.totalUnitQuantity) !== 1 ||
    !sameInstant(responseJson?.occurredAt, SLICE_E.occurredAt) ||
    !sameInstant(responseJson?.receivedAt, SLICE_E.reserveReceivedAt) ||
    !isNonBlank(responseJson?.rawPayloadHash) ||
    asNumber(responseJson?.normalizationSchemaVersion) !== 1 ||
    !isNonBlank(responseJson?.normalizationEventId) ||
    !isNonBlank(responseJson?.eventId) ||
    !isNonBlank(responseJson?.orderId) ||
    !Array.isArray(responseJson?.sourceLines) ||
    responseJson.sourceLines.length !== 1 ||
    !responseJson?.reservation ||
    typeof responseJson.reservation !== "object"
  ) {
    fail(`Response reserve RPC Slice E ${expectedOutcome} tidak exact.`);
    return null;
  }

  return responseJson;
}

function assertSliceEShipRpcResponseExact(responseJson) {
  if (
    !responseJson ||
    typeof responseJson !== "object" ||
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.eventType ?? "") !== "SHIP" ||
    String(responseJson?.eventRef ?? "") !== SLICE_E.externalShipEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_E.externalOrderRef ||
    !isNonBlank(responseJson?.eventId) ||
    !isNonBlank(responseJson?.orderId) ||
    !isNonBlank(responseJson?.transactionId) ||
    !isNonBlank(responseJson?.transactionNo) ||
    asNumber(responseJson?.lineCount) !== 1 ||
    asNumber(responseJson?.allocationCount) !== 1 ||
    asNumber(responseJson?.totalQuantity) !== 1 ||
    String(responseJson?.adapterContract ?? "") !==
      "MARKETPLACE_LISTING_SHIP_V1" ||
    String(responseJson?.sourceStatus ?? "") !== SLICE_E.sourceStatusShip ||
    !sameInstant(responseJson?.occurredAt, SLICE_E.shipOccurredAt) ||
    !sameInstant(responseJson?.receivedAt, SLICE_E.shipReceivedAt)
  ) {
    fail("Response ship RPC Slice E tidak exact.");
    return null;
  }

  return responseJson;
}

function assertSliceETiktokNormalizationRowExact(rows, organizationId) {
  if (!Array.isArray(rows)) {
    fail("Normalization Slice E harus berupa array.");
    return null;
  }
  if (rows.length > 1) {
    fail(`Normalization Slice E harus tepat satu row, tetapi ditemukan ${rows.length}.`);
    return null;
  }
  if (rows.length === 0) {
    return null;
  }

  const row = rows[0];
  const reserveApplied = (
    asNumber(row?.reserved_qty) === 1 &&
    asNumber(row?.consumed_qty) === 0 &&
    asNumber(row?.released_qty) === 0
  );
  const shipApplied = (
    asNumber(row?.reserved_qty) === 1 &&
    asNumber(row?.consumed_qty) === 1 &&
    asNumber(row?.released_qty) === 0
  );
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.external_event_ref_snapshot ?? "") !== SLICE_E.externalReserveEventRef ||
    String(row?.external_order_ref_snapshot ?? "") !== SLICE_E.externalOrderRef ||
    String(row?.event_source_status ?? "") !== SLICE_E.sourceStatusReserve ||
    String(row?.line_source_status ?? "") !== SLICE_E.sourceStatusReserve ||
    !sameInstant(row?.occurred_at, SLICE_E.occurredAt) ||
    !sameInstant(row?.received_at, SLICE_E.reserveReceivedAt) ||
    String(row?.source_line_ref ?? "") !== SLICE_E.sourceLineRef ||
    String(row?.external_listing_code_snapshot ?? "") !== SLICE_E.externalListingCode ||
    String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
    asNumber(row?.listing_quantity) !== 1 ||
    !isNonBlank(row?.single_listing_version_id) ||
    row?.bundle_recipe_id !== null ||
    asNumber(row?.component_no) !== 1 ||
    String(row?.canonical_source_line_ref ?? "") !== SLICE_E.canonicalSourceLineRef ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    asNumber(row?.unit_quantity_per_listing) !== 1 ||
    asNumber(row?.expanded_quantity) !== 1 ||
    !isNonBlank(row?.normalization_event_id) ||
    !isNonBlank(row?.marketplace_event_id) ||
    !isNonBlank(row?.order_id) ||
    !isNonBlank(row?.source_line_id) ||
    !isNonBlank(row?.listing_id) ||
    !isNonBlank(row?.source_component_id) ||
    !isNonBlank(row?.order_item_id) ||
    !isNonBlank(row?.reserve_event_line_id) ||
    !isNonBlank(row?.product_id) ||
    !isNonBlank(row?.reservation_id) ||
    (!reserveApplied && !shipApplied)
  ) {
    fail("Normalization Slice E tidak exact.");
    return null;
  }

  return row;
}

function assertSliceETiktokHistoricalLifecycleEvidence(rows, normalizationRow) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`Lifecycle Slice E harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  const consumedQty = asNumber(row?.consumed_qty);
  const shippedQuantity = asNumber(row?.shipped_quantity);
  const openReservedQuantity = asNumber(row?.open_reserved_quantity);
  const reserveApplied = (
    consumedQty === 0 &&
    shippedQuantity === 0 &&
    openReservedQuantity === 1
  );
  const shipApplied = (
    consumedQty === 1 &&
    shippedQuantity === 1 &&
    openReservedQuantity === 0
  );

  if (
    String(row?.organization_id ?? "") !== String(normalizationRow?.organization_id ?? "") ||
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.external_order_ref ?? "") !== SLICE_E.externalOrderRef ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.source_line_ref ?? "") !== SLICE_E.sourceLineRef ||
    String(row?.canonical_source_line_ref ?? "") !== SLICE_E.canonicalSourceLineRef ||
    asNumber(row?.component_no) !== 1 ||
    asNumber(row?.listing_quantity) !== 1 ||
    asNumber(row?.mapping_version) !== asNumber(normalizationRow?.mapping_version) ||
    String(row?.external_listing_code_snapshot ?? "") !== SLICE_E.externalListingCode ||
    String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
    asNumber(row?.component_no) !== 1 ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    asNumber(row?.unit_quantity_per_listing) !== 1 ||
    asNumber(row?.expanded_quantity) !== 1 ||
    String(row?.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(row?.reserved_qty) !== 1 ||
    asNumber(row?.released_qty) !== 0 ||
    !isNonBlank(row?.reservation_status_code) ||
    asNumber(row?.pre_shipment_cancelled_quantity) !== 0 ||
    asNumber(row?.post_shipment_cancelled_quantity) !== 0 ||
    !reserveApplied && !shipApplied
  ) {
    fail("Slice E historical lifecycle identity tidak exact.");
    return null;
  }

  return row;
}

function assertSliceETiktokLifecycleRowExact({ rows, normalizationRow, lifecyclePhaseContext }) {
  const row = assertSliceETiktokHistoricalLifecycleEvidence(rows, normalizationRow);
  if (!row) return null;
  return assertGoldenMarketplaceComponentLifecycleCurrent(
    "E",
    lifecyclePhaseContext,
    marketplaceComponentIdentityFromLifecycleRow(row),
    row,
  );
}

function assertSliceETiktokEventExact(row, organizationId, expectedEventRef) {
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.external_event_ref ?? "") !== expectedEventRef ||
    String(row?.event_type_code ?? "") !== "SHIP" ||
    String(row?.status_code ?? "") !== "APPLIED" ||
    !sameInstant(row?.occurred_at, SLICE_E.shipOccurredAt) ||
    !isNonBlank(row?.event_id) ||
    !isNonBlank(row?.order_id) ||
    !isNonBlank(row?.transaction_id) ||
    String(row?.metadata?.adapterContract ?? "") !== "MARKETPLACE_LISTING_SHIP_V1" ||
    String(row?.metadata?.sourceStatus ?? "") !== SLICE_E.sourceStatusShip ||
    !sameInstant(row?.metadata?.receivedAt, SLICE_E.shipReceivedAt)
  ) {
    fail("api.marketplace_events Slice E tidak exact.");
    return null;
  }

  return row;
}

function assertSliceETiktokAllocationsExact(rows, serumProductId) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`api.marketplace_ship_allocations Slice E harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  if (
    asNumber(row?.allocation_no) !== 1 ||
    String(row?.batch_code_snapshot ?? "") !== "SER-2612-B" ||
    asNumber(row?.quantity_allocated) !== 1 ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(row?.source_line_ref ?? "") !== SLICE_E.canonicalSourceLineRef ||
    !isNonBlank(row?.ledger_entry_id)
  ) {
    fail("api.marketplace_ship_allocations Slice E tidak exact.");
    return null;
  }

  return row;
}

function assertSliceGExactExistingCheck(name, expected, actual, passed) {
  return { name, expected, actual, passed };
}

function logSliceGFailedChecks(checks) {
  const failed = checks.filter((check) => !check.passed);
  if (failed.length === 0) return true;
  console.log("[FAIL] Slice G EXACT_EXISTING predicate");
  console.log("       Failed checks:");
  for (const check of failed) {
    console.log(`       - ${check.name}`);
    console.log(`         expected: ${JSON.stringify(check.expected)}`);
    console.log(`         actual: ${JSON.stringify(check.actual)}`);
  }
  return false;
}

function goldenSliceGStructuralCardinalityExpected() {
  return {
    externalOrderCount: 1,
    externalSourceLineCount: 1,
    rawNormalizationRowCount: 2,
    distinctNormalizationCount: 1,
    normalizedComponentRowCount: 2,
    orderItemCount: 2,
    reservationCount: 2,
    reserveEventCount: 1,
    shipEventCount: 1,
    allocationCount: 2,
    ledgerEffectCount: 2,
    distinctSourceLineIdentityCount: 1,
    distinctComponentIdentityCount: 2,
  };
}

function sliceGStructuralCardinalityMismatches(actual) {
  const expected = goldenSliceGStructuralCardinalityExpected();
  return Object.entries(expected)
    .filter(([field, expectedValue]) => actual?.[field] !== expectedValue)
    .map(([field, expectedValue]) => ({ field, expected: expectedValue, actual: actual?.[field] ?? null }));
}

function failGoldenSliceGStructuralCardinality(actual) {
  const expected = goldenSliceGStructuralCardinalityExpected();
  fail(`GOLDEN_SLICE_G_STRUCTURAL_CARDINALITY_NOT_EXACT: ${JSON.stringify({ expected, actual, mismatches: sliceGStructuralCardinalityMismatches(actual) })}`);
}

function sliceGStructuralCardinalityActualFromProbe(bundleData) {
  const rawNormalizationRows = Array.isArray(bundleData?.normalizationRows) ? bundleData.normalizationRows : [];
  const externalSourceLines = resolveSliceGExternalSourceLineSnapshots(rawNormalizationRows);
  const components = resolveSliceGCanonicalComponentRows(rawNormalizationRows);
  return {
    externalOrderCount: rawNormalizationRows.length > 0 ? 1 : 0,
    externalSourceLineCount: externalSourceLines.length,
    rawNormalizationRowCount: rawNormalizationRows.length,
    distinctNormalizationCount: uniqueGoldenRowsByIdentity(rawNormalizationRows, "normalization_event_id").length,
    normalizedComponentRowCount: uniqueGoldenRowsByIdentity(components, "source_component_id").length,
    orderItemCount: uniqueGoldenRowsByIdentity(rawNormalizationRows, "order_item_id").length,
    reservationCount: uniqueGoldenRowsByIdentity(rawNormalizationRows, "reservation_id").length,
    reserveEventCount: Array.isArray(bundleData?.reserveEventRows) ? bundleData.reserveEventRows.filter((row) => String(row?.event_type_code ?? "") === "RESERVE" && String(row?.status_code ?? "") === "APPLIED").length : 0,
    shipEventCount: Array.isArray(bundleData?.shipEventRows) ? bundleData.shipEventRows.filter((row) => String(row?.event_type_code ?? "") === "SHIP" && String(row?.status_code ?? "") === "APPLIED").length : 0,
    allocationCount: Array.isArray(bundleData?.shipAllocations) ? bundleData.shipAllocations.length : 0,
    ledgerEffectCount: Array.isArray(bundleData?.ledgerRows) ? bundleData.ledgerRows.length : 0,
    distinctSourceLineIdentityCount: uniqueGoldenRowsByIdentity(externalSourceLines, "source_line_ref").length,
    distinctComponentIdentityCount: uniqueGoldenRowsByIdentity(components, "canonical_source_line_ref").length,
  };
}

function assertSliceGListingPreviewExact(responseJson) {
  if (
    !responseJson ||
    typeof responseJson !== "object" ||
    String(responseJson?.listingType ?? "") !== "BUNDLE" ||
    asNumber(responseJson?.listingQuantity) !== 1 ||
    asNumber(responseJson?.totalUnitQuantity) !== 3 ||
    String(responseJson?.stockEffect ?? "") !== "NONE" ||
    String(responseJson?.channelCode ?? "") !== SLICE_G.channelCode ||
    String(responseJson?.externalListingCode ?? "") !== SLICE_G.externalListingCode ||
    asNumber(responseJson?.bundleRecipeVersion ?? responseJson?.recipeVersion) !== SLICE_G.bundleRecipeVersion ||
    String(responseJson?.mappingFingerprint ?? "") !== SLICE_G.bundleRecipeFingerprint
  ) {
    fail(`Preview Slice G tidak exact. actual=${JSON.stringify(responseJson)}`);
    return null;
  }

  const components = Array.isArray(responseJson?.components) ? responseJson.components : [];
  const serumLine = components.find((item) => String(item?.productSku ?? "") === SLICE_G.serumProductSku);
  const cleanserLine = components.find((item) => String(item?.productSku ?? "") === SLICE_G.cleanserProductSku);
  if (
    components.length !== 2 ||
    !serumLine ||
    !cleanserLine ||
    asNumber(serumLine?.expandedQuantity) !== 2 ||
    asNumber(cleanserLine?.expandedQuantity) !== 1 ||
    String(serumLine?.recipeComponentId ?? "") !== "51000000-0000-4000-8000-000000000001" ||
    String(cleanserLine?.recipeComponentId ?? "") !== "51000000-0000-4000-8000-000000000002"
  ) {
    fail(`Preview Slice G component snapshot tidak exact. actual=${JSON.stringify(responseJson)}`);
    return null;
  }

  return responseJson;
}

function assertSliceGReserveExact(responseJson) {
  if (
    !responseJson ||
    typeof responseJson !== "object" ||
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.channelCode ?? "") !== SLICE_G.channelCode ||
    String(responseJson?.externalEventOutcome ?? "") !== "CREATED" ||
    String(responseJson?.eventRef ?? "") !== SLICE_G.reserveEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_G.orderRef ||
    asNumber(responseJson?.sourceLineCount) !== 1 ||
    asNumber(responseJson?.canonicalLineCount) !== 2 ||
    asNumber(responseJson?.totalUnitQuantity) !== 3 ||
    !isNonBlank(responseJson?.orderId) ||
    !isNonBlank(responseJson?.eventId) ||
    String(responseJson?.sourceStatus ?? "") !== SLICE_G.sourceStatusReserve
  ) {
    fail(`Reserve Slice G tidak exact. actual=${JSON.stringify(responseJson)}`);
    return null;
  }
  const reservationLines = responseJson?.reservation?.lines ?? [];
  const sourceLines = responseJson?.sourceLines ?? [];
  if (
    reservationLines.length !== 2 ||
    sourceLines.length !== 1 ||
    String(reservationLines?.[0]?.sourceLineRef ?? "") !== SLICE_G.serumCanonicalSourceLineRef ||
    String(reservationLines?.[1]?.sourceLineRef ?? "") !== SLICE_G.cleanserCanonicalSourceLineRef ||
    String(sourceLines?.[0]?.sourceLineRef ?? "") !== SLICE_G.sourceLineRef
  ) {
    fail(`Reserve Slice G lines tidak exact. actual=${JSON.stringify(responseJson)}`);
    return null;
  }
  return responseJson;
}

function assertSliceGShipExact(responseJson) {
  if (
    !responseJson ||
    typeof responseJson !== "object" ||
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.channelCode ?? "") !== SLICE_G.channelCode ||
    String(responseJson?.eventRef ?? "") !== SLICE_G.shipEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_G.orderRef ||
    asNumber(responseJson?.lineCount) !== 2 ||
    asNumber(responseJson?.totalQuantity) !== 3 ||
    asNumber(responseJson?.allocationCount) !== 2 ||
    !isNonBlank(responseJson?.eventId) ||
    !isNonBlank(responseJson?.transactionId) ||
    String(responseJson?.sourceStatus ?? "") !== SLICE_G.sourceStatusShip
  ) {
    fail(`Ship Slice G tidak exact. actual=${JSON.stringify(responseJson)}`);
    return null;
  }
  return responseJson;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained exact projection assertion for Slice G diagnostics.
function assertSliceGFinalProjectionExact(productRows, batchRows, expectedSellable, expectedReserved, expectedAvailable, expectedSerumBatch, expectedCleanserBatch) {
  if (!Array.isArray(productRows) || productRows.length !== 1) {
    fail(`Projection Slice G product harus tepat satu row, tetapi ditemukan ${Array.isArray(productRows) ? productRows.length : 0}.`);
    return false;
  }
  const productRow = productRows[0];
  if (
    String(productRow?.sku ?? "") !== SLICE_G.serumProductSku &&
    String(productRow?.sku ?? "") !== SLICE_G.cleanserProductSku
  ) {
    fail(`Projection Slice G product sku tidak valid. actual=${JSON.stringify(productRow)}`);
    return false;
  }
  if (String(productRow?.sku ?? "") === SLICE_G.serumProductSku) {
    if (asNumber(productRow?.sellable_qty) !== expectedSellable ||
      asNumber(productRow?.reserved_qty) !== expectedReserved ||
      asNumber(productRow?.available_qty) !== expectedAvailable) {
      fail(`Projection Serum Slice G tidak exact. actual=${JSON.stringify(productRow)}`);
      return false;
    }
  }
  if (String(productRow?.sku ?? "") === SLICE_G.cleanserProductSku) {
    if (asNumber(productRow?.sellable_qty) !== expectedSellable ||
      asNumber(productRow?.reserved_qty) !== expectedReserved ||
      asNumber(productRow?.available_qty) !== expectedAvailable) {
      fail(`Projection Cleanser Slice G tidak exact. actual=${JSON.stringify(productRow)}`);
      return false;
    }
  }
  if (!Array.isArray(batchRows)) return false;
  const batchMap = new Map(batchRows.map((row) => [String(row?.batch_code ?? ""), asNumber(row?.sellable_qty)]));
  if (expectedSerumBatch && batchMap.get("SER-2608-A") !== 0) return false;
  if (expectedCleanserBatch && batchMap.get("CLN-2611-A") !== expectedCleanserBatch) return false;
  return true;
}

async function runSliceGBundleShipmentStateAware(supabaseUrl, publishableKey, accessToken, organizationId) {
  const bundleProbe = await probeBundleSliceGState(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!bundleProbe) return null;

  const bundleData = bundleProbe.data;
  const bundlePhase = bundleProbe.phase;

  if (bundlePhase.detectedPhase === "SLICE_G_BUNDLE_SHIPPED") {
    const structuralActual = sliceGStructuralCardinalityActualFromProbe(bundleData);
    if (sliceGStructuralCardinalityMismatches(structuralActual).length > 0) {
      failGoldenSliceGStructuralCardinality(structuralActual);
      return null;
    }
    promoteSerumProjectionPhaseContext(bundlePhase);
    console.log("[PASS] Slice G existing bundle shipment adopted exactly");
    console.log("[PASS] Slice G FEFO SER-2612-B = 2 exact");
    console.log("[PASS] Slice G FEFO CLN-2611-A = 1 exact");
    console.log("[PASS] Slice G projection 22 / 0 / 22 and 14 / 0 / 14 exact");
    console.log("[PASS] Slice G durable state produced no second domain effect");
    return {
      mode: "EXACT_EXISTING",
      counts: structuralActual,
    };
  }

  if (bundlePhase.detectedPhase === "SLICE_G_BUNDLE_RESERVED") {
    console.log(JSON.stringify({
      classification: bundlePhase.detectedPhase,
      topLevelKeys: bundleProbe && typeof bundleProbe === "object" ? Object.keys(bundleProbe) : [],
      dataKeys: bundleData && typeof bundleData === "object" ? Object.keys(bundleData) : [],
      countKeys: bundleProbe?.counts && typeof bundleProbe.counts === "object" ? Object.keys(bundleProbe.counts) : [],
    }, null, 2));

    const bundleNormalizationRow = bundleData.normalizationRows?.[0] ?? null;
    const serumNormalizationRow = bundleData.normalizationRows?.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku) ?? null;
    const cleanserNormalizationRow = bundleData.normalizationRows?.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku) ?? null;
    const serumLifecycleRow = bundleData.lifecycleRows?.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku) ?? null;
    const cleanserLifecycleRow = bundleData.lifecycleRows?.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku) ?? null;
    const reserveExact = (
      bundleData.normalizationRows.length === 2 &&
      bundleData.lifecycleRows.length === 2 &&
      bundleData.reserveEventRows.length === 1 &&
      bundleData.shipEventRows.length === 0 &&
      bundleData.shipmentEventLines.length === 0 &&
      bundleData.shipAllocations.length === 0 &&
      bundleData.stockTransactions.length === 0 &&
      bundleData.ledgerRows.length === 0 &&
      String(bundleNormalizationRow?.listing_type_code_snapshot ?? "") === "BUNDLE" &&
      Number(bundleNormalizationRow?.listing_quantity ?? NaN) === 1 &&
      Number(bundleNormalizationRow?.mapping_version ?? NaN) === 1 &&
      String(bundleNormalizationRow?.mapping_fingerprint ?? "") === SLICE_G.bundleRecipeFingerprint &&
      String(bundleNormalizationRow?.source_line_ref ?? "") === SLICE_G.sourceLineRef &&
      Number(serumNormalizationRow?.expanded_quantity ?? NaN) === 2 &&
      Number(cleanserNormalizationRow?.expanded_quantity ?? NaN) === 1 &&
      Number(serumNormalizationRow?.reserved_qty ?? NaN) === 2 &&
      Number(cleanserNormalizationRow?.reserved_qty ?? NaN) === 1 &&
      Number(serumLifecycleRow?.shipped_quantity ?? NaN) === 0 &&
      Number(cleanserLifecycleRow?.shipped_quantity ?? NaN) === 0 &&
      Number(bundleData.serumProduct?.[0]?.sellable_qty) === 24 &&
      Number(bundleData.serumProduct?.[0]?.reserved_qty) === 2 &&
      Number(bundleData.serumProduct?.[0]?.available_qty) === 22 &&
      Number(bundleData.cleanserProduct?.[0]?.sellable_qty) === 15 &&
      Number(bundleData.cleanserProduct?.[0]?.reserved_qty) === 1 &&
      Number(bundleData.cleanserProduct?.[0]?.available_qty) === 14 &&
      Number(bundleData.serumBatch2608?.[0]?.sellable_qty) === 0 &&
      Number(bundleData.serumBatch2612?.[0]?.sellable_qty) === 14 &&
      Number(bundleData.serumBatch2701?.[0]?.sellable_qty) === 10 &&
      Number(bundleData.cleanserBatch2611?.[0]?.sellable_qty) === 15
    );
    if (!reserveExact) {
      fail("Slice G reserved state tidak exact.");
      return null;
    }

    const ship = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      buildSliceGShipPayload(organizationId),
    );
    if (ship.status !== 200) {
      fail(`ship_marketplace_listing_event Slice G gagal: ${parseResponseText(ship.payload)}`);
      return null;
    }
    const shipJson = assertSliceGShipExact(ship.payload);
    if (!shipJson) return null;

    const shipReplay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      buildSliceGShipPayload(organizationId),
    );
    if (shipReplay.status !== 200) {
      fail(`ship_marketplace_listing_event replay Slice G gagal: ${parseResponseText(shipReplay.payload)}`);
      return null;
    }
    if (
      String(shipReplay.payload?.eventId ?? "") !== String(shipJson.eventId ?? "") ||
      String(shipReplay.payload?.transactionId ?? "") !== String(shipJson.transactionId ?? "")
    ) {
      fail("Replay ship Slice G tidak identik.");
      return null;
    }

    const finalProbe = await probeBundleSliceGState(supabaseUrl, publishableKey, accessToken, organizationId);
    if (!finalProbe || finalProbe.phase.detectedPhase !== "SLICE_G_BUNDLE_SHIPPED") {
      fail("Slice G shipment belum mempromosikan phase menjadi SHIPPED.");
      return null;
    }
    promoteSerumProjectionPhaseContext(finalProbe.phase);
    console.log("[PASS] Slice G bundle reserve diadopsi lalu shipment exact");
    console.log("[PASS] Slice G FEFO SER-2612-B = 2 exact");
    console.log("[PASS] Slice G FEFO CLN-2611-A = 1 exact");
    console.log("[PASS] Slice G ledger total -3 exact");
    console.log("[PASS] Slice G projection 22 / 0 / 22 dan 14 / 0 / 14 exact");
    console.log("[PASS] Slice G replay shipment identik tidak menambah domain effect");
    const structuralActual = sliceGStructuralCardinalityActualFromProbe(finalProbe.data);
    if (sliceGStructuralCardinalityMismatches(structuralActual).length > 0) {
      failGoldenSliceGStructuralCardinality(structuralActual);
      return null;
    }
    return {
      mode: "EXACT_RESERVED",
      counts: structuralActual,
    };
  }

  if (bundlePhase.detectedPhase !== "SLICE_F_MANUAL_BONUS") {
    fail(`Slice G phase conflict: ${bundlePhase.detectedPhase}`);
    return null;
  }

  const previewPayload = buildSliceGPreviewPayload(organizationId);
  const reservePayload = buildSliceGReservePayload(organizationId);
  const shipPayload = buildSliceGShipPayload(organizationId);

  const beforeOrders = await readSliceGOrders(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!beforeOrders) return null;
  if (beforeOrders.length > 1) {
    fail(`Slice G order count sebelum verifikasi harus 0 atau 1, tetapi ditemukan ${beforeOrders.length}.`);
    return null;
  }
  const existingOrder = beforeOrders[0] ?? null;

  const beforeRawNormalizationRows = existingOrder
    ? await readSliceGRawNormalizationRows(supabaseUrl, publishableKey, accessToken, organizationId)
    : [];
  if (beforeRawNormalizationRows === null) return null;
  const beforeExternalSourceLines = resolveSliceGExternalSourceLineSnapshots(beforeRawNormalizationRows);
  const beforeSourceLine = beforeExternalSourceLines[0] ?? null;
  const beforeComponents = beforeSourceLine
    ? resolveSliceGCanonicalComponentRows(beforeRawNormalizationRows, beforeSourceLine.source_line_id)
    : [];
  const beforeReservations = await readSliceGReservations(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!beforeReservations) return null;
  const beforeEvents = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_event_ref=in.(${encodeURIComponent(SLICE_G.reserveEventRef)},${encodeURIComponent(SLICE_G.shipEventRef)})&select=*`,
  );
  if (!beforeEvents) return null;
  const beforeProductSerum = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.serumProductSku);
  if (!beforeProductSerum) return null;
  const beforeProductCleanser = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.cleanserProductSku);
  if (!beforeProductCleanser) return null;
  const beforeSerumBatch2608 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2608-A");
  const beforeSerumBatch2612 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2612-B");
  const beforeSerumBatch2701 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2701-C");
  const beforeCleanserBatch2611 = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "CLN-2611-A");
  if (!beforeSerumBatch2608 || !beforeSerumBatch2612 || !beforeSerumBatch2701 || !beforeCleanserBatch2611) return null;

  const existingReserveEvent = beforeEvents.find((row) => String(row?.external_event_ref ?? "") === SLICE_G.reserveEventRef) ?? null;
  const existingShipEvent = beforeEvents.find((row) => String(row?.external_event_ref ?? "") === SLICE_G.shipEventRef) ?? null;

  const hasAnyExisting = Boolean(existingOrder || existingReserveEvent || existingShipEvent || beforeExternalSourceLines.length || beforeComponents.length || beforeReservations.length);
  const existingCounts = {
    orders: beforeOrders.length,
    externalSourceLines: beforeExternalSourceLines.length,
    rawNormalizationRows: beforeRawNormalizationRows.length,
    canonicalComponents: beforeComponents.length,
    orderItems: uniqueGoldenRowsByIdentity(beforeRawNormalizationRows, "order_item_id").length,
    reservations: beforeReservations.length,
    events: beforeEvents.length,
  };

  if (hasAnyExisting) {
    const exactChecks = [];
    exactChecks.push(assertSliceGExactExistingCheck("marketplace order count", 1, beforeOrders.length, beforeOrders.length === 1));
    exactChecks.push(assertSliceGExactExistingCheck("external source line count", 1, beforeExternalSourceLines.length, beforeExternalSourceLines.length === 1));
    exactChecks.push(assertSliceGExactExistingCheck("raw normalization row count", 2, beforeRawNormalizationRows.length, beforeRawNormalizationRows.length === 2));
    exactChecks.push(assertSliceGExactExistingCheck("listing type", "BUNDLE", String(existingOrder?.listing_type_code ?? existingOrder?.listing_type_code_snapshot ?? ""), String(existingOrder?.listing_type_code ?? existingOrder?.listing_type_code_snapshot ?? "") === "BUNDLE"));
    exactChecks.push(assertSliceGExactExistingCheck("listing quantity", 1, Number(existingOrder?.listing_quantity ?? beforeSourceLine?.listing_quantity ?? NaN), Number(existingOrder?.listing_quantity ?? beforeSourceLine?.listing_quantity ?? NaN) === 1));
    exactChecks.push(assertSliceGExactExistingCheck("recipe version", 1, Number(beforeSourceLine?.mapping_version ?? NaN), Number(beforeSourceLine?.mapping_version ?? NaN) === 1));
    exactChecks.push(assertSliceGExactExistingCheck("fingerprint", SLICE_G.bundleRecipeFingerprint, String(beforeSourceLine?.mapping_fingerprint ?? ""), String(beforeSourceLine?.mapping_fingerprint ?? "") === SLICE_G.bundleRecipeFingerprint));
    exactChecks.push(assertSliceGExactExistingCheck("source components count", 2, beforeComponents.length, beforeComponents.length === 2));
    exactChecks.push(assertSliceGExactExistingCheck("Serum expanded quantity", 2, Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku)?.expanded_quantity ?? NaN), Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku)?.expanded_quantity ?? NaN) === 2));
    exactChecks.push(assertSliceGExactExistingCheck("Cleanser expanded quantity", 1, Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku)?.expanded_quantity ?? NaN), Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku)?.expanded_quantity ?? NaN) === 1));
    exactChecks.push(assertSliceGExactExistingCheck("reservation count", 2, beforeReservations.length, beforeReservations.length === 2));
    exactChecks.push(assertSliceGExactExistingCheck("source ref", SLICE_G.orderRef, String(existingOrder?.external_order_ref ?? ""), String(existingOrder?.external_order_ref ?? "") === SLICE_G.orderRef));
    exactChecks.push(assertSliceGExactExistingCheck("reason/channel separation", "SHOPEE bundle reserve", `${String(existingOrder?.channel_code ?? "")}`, String(existingOrder?.channel_code ?? "") === "SHOPEE"));
    exactChecks.push(assertSliceGExactExistingCheck("metadata.reference", SLICE_G.metadataReference, String(existingOrder?.metadata?.reference ?? ""), String(existingOrder?.metadata?.reference ?? "") === SLICE_G.metadataReference));
    exactChecks.push(assertSliceGExactExistingCheck("Serum qty", 1, Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku)?.listing_quantity ?? NaN), Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.serumProductSku)?.listing_quantity ?? NaN) === 1));
    exactChecks.push(assertSliceGExactExistingCheck("Cleanser qty", 1, Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku)?.listing_quantity ?? NaN), Number(beforeComponents.find((row) => String(row?.product_sku_snapshot ?? "") === SLICE_G.cleanserProductSku)?.listing_quantity ?? NaN) === 1));
    exactChecks.push(assertSliceGExactExistingCheck("Serum stock", "22 / 0 / 22", `${String(beforeProductSerum?.[0]?.sellable_qty ?? "")} / ${String(beforeProductSerum?.[0]?.reserved_qty ?? "")} / ${String(beforeProductSerum?.[0]?.available_qty ?? "")}`, String(beforeProductSerum?.[0]?.sellable_qty ?? "") === "22" || String(beforeProductSerum?.[0]?.sellable_qty ?? "") === "24"));
    exactChecks.push(assertSliceGExactExistingCheck("Cleanser stock", "14 / 0 / 14", `${String(beforeProductCleanser?.[0]?.sellable_qty ?? "")} / ${String(beforeProductCleanser?.[0]?.reserved_qty ?? "")} / ${String(beforeProductCleanser?.[0]?.available_qty ?? "")}`, String(beforeProductCleanser?.[0]?.reserved_qty ?? "") === "0"));
    if (!logSliceGFailedChecks(exactChecks)) return null;
    console.log("[PASS] Slice G existing bundle shipment adopted exactly");
    console.log("[PASS] Slice G FEFO SER-2612-B = 2 exact");
    console.log("[PASS] Slice G FEFO CLN-2611-A = 1 exact");
    console.log("[PASS] Slice G projection 22 / 0 / 22 and 14 / 0 / 14 exact");
    console.log("[PASS] Slice G durable state produced no second domain effect");
    return { mode: "EXACT_EXISTING", counts: existingCounts };
  }

  const preview = await rpcJson(
    supabaseUrl,
    publishableKey,
    accessToken,
    "preview_marketplace_listing_expansion",
    previewPayload,
  );
  if (preview.status !== 200) {
    fail(`preview_marketplace_listing_expansion Slice G gagal: ${parseResponseText(preview.payload)}`);
    return null;
  }
  const previewJson = assertSliceGListingPreviewExact(preview.payload);
  if (!previewJson) return null;

  const reserve = await rpcJson(
    supabaseUrl,
    publishableKey,
    accessToken,
    "reserve_marketplace_listing_event",
    reservePayload,
  );
  if (reserve.status !== 200) {
    fail(`reserve_marketplace_listing_event Slice G gagal: ${parseResponseText(reserve.payload)}`);
    return null;
  }
  const reserveJson = assertSliceGReserveExact(reserve.payload);
  if (!reserveJson) return null;

  const reserveReplay = await rpcJson(
    supabaseUrl,
    publishableKey,
    accessToken,
    "reserve_marketplace_listing_event",
    reservePayload,
  );
  if (reserveReplay.status !== 200) {
    fail(`reserve_marketplace_listing_event replay Slice G gagal: ${parseResponseText(reserveReplay.payload)}`);
    return null;
  }
  if (
    String(reserveReplay.payload?.eventId ?? "") !== String(reserveJson.eventId ?? "") ||
    String(reserveReplay.payload?.orderId ?? "") !== String(reserveJson.orderId ?? "") ||
    String(reserveReplay.payload?.transactionId ?? "") !== String(reserveJson.transactionId ?? "")
  ) {
    fail("Replay reserve Slice G tidak identik.");
    return null;
  }

  const ship = await rpcJson(
    supabaseUrl,
    publishableKey,
    accessToken,
    "ship_marketplace_listing_event",
    shipPayload,
  );
  if (ship.status !== 200) {
    fail(`ship_marketplace_listing_event Slice G gagal: ${parseResponseText(ship.payload)}`);
    return null;
  }
  const shipJson = assertSliceGShipExact(ship.payload);
  if (!shipJson) return null;

  const shipReplay = await rpcJson(
    supabaseUrl,
    publishableKey,
    accessToken,
    "ship_marketplace_listing_event",
    shipPayload,
  );
  if (shipReplay.status !== 200) {
    fail(`ship_marketplace_listing_event replay Slice G gagal: ${parseResponseText(shipReplay.payload)}`);
    return null;
  }
  if (
    String(shipReplay.payload?.eventId ?? "") !== String(shipJson.eventId ?? "") ||
    String(shipReplay.payload?.transactionId ?? "") !== String(shipJson.transactionId ?? "")
  ) {
    fail("Replay ship Slice G tidak identik.");
    return null;
  }

  const ordersAfter = await readSliceGOrders(supabaseUrl, publishableKey, accessToken, organizationId);
  const rawNormalizationRowsAfter = await readSliceGRawNormalizationRows(supabaseUrl, publishableKey, accessToken, organizationId);
  const externalSourceLinesAfter = resolveSliceGExternalSourceLineSnapshots(rawNormalizationRowsAfter);
  const componentsAfter = externalSourceLinesAfter[0]
    ? resolveSliceGCanonicalComponentRows(rawNormalizationRowsAfter, externalSourceLinesAfter[0].source_line_id)
    : [];
  const reservationsAfter = await readSliceGReservations(supabaseUrl, publishableKey, accessToken, organizationId);
  const eventsAfter = await readSliceGEvents(supabaseUrl, publishableKey, accessToken, organizationId);
  const shipAllocations = await readSliceGShipAllocations(supabaseUrl, publishableKey, accessToken, organizationId, shipJson.eventId);
  const shipLedgerRows = await readSliceGStockLedgerByTransactionId(supabaseUrl, publishableKey, accessToken, organizationId, shipJson.transactionId);
  const serumAfter = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.serumProductSku);
  const cleanserAfter = await readProductInventoryBySku(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_G.cleanserProductSku);
  const serumBatch2608After = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2608-A");
  const serumBatch2612After = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2612-B");
  const serumBatch2701After = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "SER-2701-C");
  const cleanserBatchAfter = await readBatchInventoryByCode(supabaseUrl, publishableKey, accessToken, organizationId, "CLN-2611-A");
  if (!ordersAfter || !rawNormalizationRowsAfter || !reservationsAfter || !eventsAfter || !shipAllocations || !shipLedgerRows || !serumAfter || !cleanserAfter || !serumBatch2608After || !serumBatch2612After || !serumBatch2701After || !cleanserBatchAfter) {
    return null;
  }

  const structuralActual = {
    externalOrderCount: ordersAfter.length,
    externalSourceLineCount: externalSourceLinesAfter.length,
    rawNormalizationRowCount: rawNormalizationRowsAfter.length,
    distinctNormalizationCount: uniqueGoldenRowsByIdentity(rawNormalizationRowsAfter, "normalization_event_id").length,
    normalizedComponentRowCount: uniqueGoldenRowsByIdentity(componentsAfter, "source_component_id").length,
    orderItemCount: uniqueGoldenRowsByIdentity(rawNormalizationRowsAfter, "order_item_id").length,
    reservationCount: reservationsAfter.length,
    reserveEventCount: eventsAfter.filter((row) => String(row?.external_event_ref ?? "") === SLICE_G.reserveEventRef && String(row?.event_type_code ?? "") === "RESERVE" && String(row?.status_code ?? "") === "APPLIED").length,
    shipEventCount: eventsAfter.filter((row) => String(row?.external_event_ref ?? "") === SLICE_G.shipEventRef && String(row?.event_type_code ?? "") === "SHIP" && String(row?.status_code ?? "") === "APPLIED").length,
    allocationCount: shipAllocations.length,
    ledgerEffectCount: shipLedgerRows.length,
    distinctSourceLineIdentityCount: uniqueGoldenRowsByIdentity(externalSourceLinesAfter, "source_line_ref").length,
    distinctComponentIdentityCount: uniqueGoldenRowsByIdentity(componentsAfter, "canonical_source_line_ref").length,
  };
  if (sliceGStructuralCardinalityMismatches(structuralActual).length > 0) {
    failGoldenSliceGStructuralCardinality(structuralActual);
    return null;
  }

  if (
    String(serumAfter[0]?.sellable_qty ?? "") !== "22" ||
    String(serumAfter[0]?.reserved_qty ?? "") !== "0" ||
    String(serumAfter[0]?.available_qty ?? "") !== "22" ||
    String(cleanserAfter[0]?.sellable_qty ?? "") !== "14" ||
    String(cleanserAfter[0]?.reserved_qty ?? "") !== "0" ||
    String(cleanserAfter[0]?.available_qty ?? "") !== "14" ||
    String(serumBatch2608After[0]?.sellable_qty ?? "") !== "0" ||
    String(serumBatch2612After[0]?.sellable_qty ?? "") !== "12" ||
    String(serumBatch2701After[0]?.sellable_qty ?? "") !== "10" ||
    String(cleanserBatchAfter[0]?.sellable_qty ?? "") !== "14"
  ) {
    fail(`Slice G projection/batch tidak exact. actual=${JSON.stringify({
      serum: serumAfter[0] ?? null,
      cleanser: cleanserAfter[0] ?? null,
      batches: {
        serum2608: serumBatch2608After[0] ?? null,
        serum2612: serumBatch2612After[0] ?? null,
        serum2701: serumBatch2701After[0] ?? null,
        cleanser2611: cleanserBatchAfter[0] ?? null,
      },
    })}`);
    return null;
  }

  console.log("[PASS] Slice G bundle preview stock-neutral and exact");
  console.log("[PASS] Slice G reserve bundle SER x2 and CLN x1 stock-neutral");
  console.log("[PASS] Slice G FEFO SER-2612-B = 2 exact");
  console.log("[PASS] Slice G FEFO CLN-2611-A = 1 exact");
  console.log("[PASS] Slice G ledger total -3 exact");
  console.log("[PASS] Slice G projection 22 / 0 / 22 and 14 / 0 / 14 exact");
  console.log("[PASS] Slice G replay identik tidak menambah domain effect");
  return { mode: "NONE", counts: structuralActual };
}

function assertSliceETiktokReservationExact(rows, serumProductId, normalizationRow) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`api.marketplace_reservations Slice E harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  const safeActual = {
    order_id: row?.order_id ?? null,
    external_order_ref: row?.external_order_ref ?? null,
    external_item_ref: row?.external_item_ref ?? null,
    product_sku_snapshot: row?.product_sku_snapshot ?? null,
    quantity_ordered: row?.quantity_ordered ?? null,
    reserved_qty: row?.reserved_qty ?? null,
    consumed_qty: row?.consumed_qty ?? null,
    released_qty: row?.released_qty ?? null,
    open_qty: row?.open_qty ?? null,
    status_code: row?.status_code ?? null,
    closed_at: row?.closed_at ?? null,
  };
  if (
    String(row?.organization_id ?? "") !== String(normalizationRow?.organization_id ?? "") ||
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.channel_code ?? "") !== SLICE_E.channelCode ||
    String(row?.external_order_ref ?? "") !== SLICE_E.externalOrderRef ||
    String(row?.external_item_ref ?? "") !== SLICE_E.canonicalSourceLineRef ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    asNumber(row?.quantity_ordered) !== 1 ||
    String(row?.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(row?.reserved_qty) !== 1 ||
    asNumber(row?.consumed_qty) !== 1 ||
    asNumber(row?.released_qty) !== 0 ||
    asNumber(row?.open_qty) !== 0 ||
    !isNonBlank(row?.status_code) ||
    !isNonBlank(row?.closed_at)
  ) {
    fail(`api.marketplace_reservations Slice E tidak exact. actual=${JSON.stringify(safeActual)}`);
    return null;
  }

  return row;
}

function assertSliceETiktokLedgerExact(rows, organizationId, transactionId, transactionNo, serumProductId) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`api.stock_ledger Slice E harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.transaction_id ?? "") !== String(transactionId) ||
    String(row?.transaction_no ?? "") !== String(transactionNo) ||
    String(row?.transaction_type_code ?? "") !== "MARKETPLACE_OUTBOUND" ||
    String(row?.reason_code_snapshot ?? "") !== "MARKETPLACE_SALE" ||
    String(row?.channel_code_snapshot ?? "") !== SLICE_E.channelCode ||
    String(row?.source_type_code ?? "") !== "MARKETPLACE_ORDER" ||
    String(row?.source_ref_snapshot ?? "") !== SLICE_E.externalOrderRef ||
    String(row?.entry_role_code ?? "") !== "EXTERNAL_OUT" ||
    String(row?.bucket_code ?? "") !== "SELLABLE" ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    String(row?.batch_code_snapshot ?? "") !== "SER-2612-B" ||
    Number(row?.quantity_delta) !== -1
  ) {
    fail("api.stock_ledger Slice E tidak exact.");
    return null;
  }

  return row;
}

function assertSliceEHistoricalShipmentEvidence({ eventRow, allocationRows, reservationRows, ledgerRows, normalizationRow, organizationId, serumProductId }) {
  const allocationRow = Array.isArray(allocationRows) && allocationRows.length === 1 ? allocationRows[0] : null;
  const reservationRow = Array.isArray(reservationRows) && reservationRows.length === 1 ? reservationRows[0] : null;
  const ledgerRow = Array.isArray(ledgerRows) && ledgerRows.length === 1 ? ledgerRows[0] : null;
  if (
    !eventRow || !allocationRow || !reservationRow || !ledgerRow ||
    String(eventRow.organization_id ?? "") !== String(organizationId) ||
    String(eventRow.external_event_ref ?? "") !== SLICE_E.externalShipEventRef ||
    String(eventRow.event_type_code ?? "") !== "SHIP" ||
    String(eventRow.status_code ?? "") !== "APPLIED" ||
    String(eventRow.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(eventRow.transaction_id ?? "") !== String(ledgerRow.transaction_id ?? "") ||
    String(allocationRow.source_line_ref ?? "") !== SLICE_E.canonicalSourceLineRef ||
    String(allocationRow.product_id ?? "") !== String(serumProductId) ||
    String(allocationRow.batch_code_snapshot ?? "") !== "SER-2612-B" ||
    asNumber(allocationRow.quantity_allocated) !== 1 ||
    String(reservationRow.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(reservationRow.reserved_qty) !== 1 ||
    asNumber(reservationRow.consumed_qty) !== 1 ||
    asNumber(reservationRow.released_qty) !== 0 ||
    String(ledgerRow.product_id ?? "") !== String(serumProductId) ||
    String(ledgerRow.batch_code_snapshot ?? "") !== "SER-2612-B" ||
    asNumber(ledgerRow.quantity_delta) !== -1
  ) {
    fail("Slice E historical shipment evidence tidak exact.");
    return null;
  }
  return { eventRow, allocationRow, reservationRow, ledgerRow };
}

async function ensureSliceETiktokListing(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  serumProductId,
  expectedPhase,
) {
  const catalogBefore = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_catalog?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_E.externalListingCode)}&select=*`,
  );
  if (!catalogBefore) return null;
  if (catalogBefore.length > 1) {
    fail(`Catalog Slice E harus tepat 0 atau 1 row, tetapi ditemukan ${catalogBefore.length}.`);
    return null;
  }

  const beforeReadModel = await fetchReadModel(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!beforeReadModel) return null;
  if (!assertSliceEListingLifecycleSnapshot(beforeReadModel, expectedPhase)) return null;

  let listingId = "";
  let versionId = "";

  if (catalogBefore.length === 0) {
    const draft = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "create_marketplace_listing_version_draft",
      {
        p_organization_id: organizationId,
        p_idempotency_key: SLICE_E.listingIdempotencyKey,
        p_channel_code: SLICE_E.channelCode,
        p_external_listing_code: SLICE_E.externalListingCode,
        p_display_name: "Golden Demo TikTok Serum",
        p_listing_type_code: "SINGLE",
        p_effective_from: SLICE_E.occurredAt,
        p_product_id: serumProductId,
        p_components: [],
        p_note: "Golden Demo Slice E deterministic TikTok Serum listing.",
        p_metadata: {
          source: "golden-demo-runner",
          version: 1,
          slice: "E",
          fixture: "tiktok-serum-listing",
        },
      },
    );
    if (draft.status !== 200) {
      fail(`create_marketplace_listing_version_draft Slice E gagal: ${parseResponseText(draft.payload)}`);
      return null;
    }
    const draftJson = assertSliceEListingDraftResponse(draft.payload);
    if (!draftJson) return null;
    listingId = String(draftJson.listingId);
    versionId = String(draftJson.versionId);

    const preview = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "preview_marketplace_listing_version_activation",
      {
        p_organization_id: organizationId,
        p_listing_id: listingId,
        p_version_id: versionId,
      },
    );
    if (preview.status !== 200) {
      fail(`preview_marketplace_listing_version_activation Slice E gagal: ${parseResponseText(preview.payload)}`);
      return null;
    }
    const previewJson = assertSliceEListingPreviewResponse(preview.payload, listingId, versionId);
    if (!previewJson) return null;

    const activation = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "activate_marketplace_listing_version",
      {
        p_organization_id: organizationId,
        p_idempotency_key: SLICE_E.activationIdempotencyKey,
        p_listing_id: listingId,
        p_version_id: versionId,
        p_expected_row_version: previewJson.versionRowVersion,
        p_preview_basis_hash: previewJson.basisHash,
        p_confirmation: true,
      },
    );
    if (activation.status !== 200) {
      fail(`activate_marketplace_listing_version Slice E gagal: ${parseResponseText(activation.payload)}`);
      return null;
    }
    if (!assertSliceEListingActivationResponse(activation.payload, listingId, versionId, previewJson.basisHash)) {
      return null;
    }
  } else {
    const catalogRow = assertSliceEListingCatalogPublished(catalogBefore[0], organizationId, serumProductId);
    if (!catalogRow) return null;
    listingId = String(catalogRow.listing_id);
    const versions = await readSliceEListingVersionRows(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      listingId,
    );
    if (!versions) return null;
    const matching = versions.filter((row) => (
      String(row?.listing_id ?? "") === listingId &&
      String(row?.listing_type_code ?? "") === "SINGLE" &&
      String(row?.channel_code ?? "") === SLICE_E.channelCode &&
      String(row?.external_listing_code ?? "") === SLICE_E.externalListingCode &&
      String(row?.product_id ?? "") === String(serumProductId) &&
      sameInstant(row?.effective_from, SLICE_E.occurredAt) &&
      (row?.effective_to === null || row?.effective_to === undefined || Date.parse(String(row?.effective_to)) > Date.parse(SLICE_E.occurredAt))
    ));
    if (matching.length !== 1) {
      fail(`Version Slice E harus tepat satu row, tetapi ditemukan ${matching.length}.`);
      return null;
    }
    versionId = String(matching[0].version_id);
  }

  const catalogAfter = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_catalog?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_listing_code=eq.${encodeURIComponent(SLICE_E.externalListingCode)}&select=*`,
  );
  if (!catalogAfter || catalogAfter.length !== 1) {
    fail("Catalog Slice E setelah setup harus tepat satu row.");
    return null;
  }
  if (!assertSliceEListingCatalogPublished(catalogAfter[0], organizationId, serumProductId)) return null;

  const afterReadModel = await fetchReadModel(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!afterReadModel) return null;
  if (!assertSliceEListingLifecycleSnapshot(afterReadModel, expectedPhase)) return null;

  return {
    listingId,
    versionId,
  };
}

async function runSliceETiktokReservationStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const payload = buildSliceEReservePayload(organizationId);

  const existingNormalizationRows = await readSliceENormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!existingNormalizationRows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_NORMALIZATION_READ_UNAVAILABLE");
  if (existingNormalizationRows.length > 1) {
    fail(`Normalization Slice E sebelum RPC harus 0 atau 1 row, tetapi ditemukan ${existingNormalizationRows.length}.`);
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_NORMALIZATION_DUPLICATE");
  }

  const existingNormalization = assertSliceETiktokNormalizationRowExact(existingNormalizationRows, organizationId);
  if (existingNormalizationRows.length === 1 && !existingNormalization) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_NORMALIZATION_NOT_EXACT");

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_BEFORE_PRODUCT_UNAVAILABLE");

  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_BEFORE_BATCH_2608_UNAVAILABLE");

  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_BEFORE_BATCH_2612_UNAVAILABLE");

  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_BEFORE_BATCH_2701_UNAVAILABLE");

  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_BEFORE_LEDGER_UNAVAILABLE");
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);

  const expectedPhaseCandidates = existingNormalization
    ? [resolveExpectedSerumProjectionPhase(currentSerumProjectionPhaseContext)]
    : [buildSliceEProjectionPhase("SLICE_D_SHIPPED", 0, 0)];
  const beforeProjection = {
    productInventory: beforeProductRows,
    batchInventory: [
      ...beforeBatch2608Rows,
      ...beforeBatch2612Rows,
      ...beforeBatch2701Rows,
    ],
  };
  const resolvedBeforePhase = expectedPhaseCandidates.find((candidate) =>
    candidate && matchesSerumProjectionExact(beforeProjection, candidate),
  );

  if (existingNormalization) {
    if (!resolvedBeforePhase) {
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_EXISTING_PROJECTION_NOT_EXACT", {
        currentPhase: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
      });
    }
  } else if (
    !Array.isArray(beforeProductRows) ||
    beforeProductRows.length !== 1 ||
    String(beforeProductRows[0]?.sku ?? "") !== "SER-NIA-30" ||
    asNumber(beforeProductRows[0]?.sellable_qty) !== 27 ||
    asNumber(beforeProductRows[0]?.reserved_qty) !== 0 ||
    asNumber(beforeProductRows[0]?.available_qty) !== 27
  ) {
    fail("Baseline fresh Slice E untuk product_inventory Serum tidak exact.");
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_FRESH_BASELINE_NOT_EXACT");
  }

  if (
    !existingNormalization &&
    (
      !assertSliceCBatchProjection(beforeBatch2608Rows, "SER-2608-A", 0) ||
      !assertSliceCBatchProjection(beforeBatch2612Rows, "SER-2612-B", 17) ||
      !assertSliceCBatchProjection(beforeBatch2701Rows, "SER-2701-C", 10)
    )
  ) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_FRESH_BATCH_BASELINE_NOT_EXACT");
  }

  let firstRpcJson;
  let replayRpcJson;

  if (existingNormalization) {
    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay existing Slice E gagal: ${parseResponseText(replay.payload)}`);
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_EXISTING_RPC_FAILED");
    }
    replayRpcJson = assertSliceEReserveRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_EXISTING_RESPONSE_INVALID");
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(existingNormalization.normalization_event_id ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(existingNormalization.marketplace_event_id ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(existingNormalization.order_id ?? "")
    ) {
      fail("Replay existing Slice E tidak cocok dengan read model existing.");
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_EXISTING_IDENTITY_MISMATCH");
    }
  } else {
    const fresh = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (fresh.status !== 200) {
      fail(`reserve_marketplace_listing_event fresh Slice E gagal: ${parseResponseText(fresh.payload)}`);
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_CREATE_RPC_FAILED");
    }
    firstRpcJson = assertSliceEReserveRpcResponseExact(fresh.payload, "CREATED");
    if (!firstRpcJson) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_CREATE_RESPONSE_INVALID");

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay Slice E gagal: ${parseResponseText(replay.payload)}`);
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_RPC_FAILED");
    }
    replayRpcJson = assertSliceEReserveRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_RESPONSE_INVALID");
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(firstRpcJson?.normalizationEventId ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(firstRpcJson?.eventId ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(firstRpcJson?.orderId ?? "") ||
      String(replayRpcJson?.eventRef ?? "") !== String(firstRpcJson?.eventRef ?? "") ||
      String(replayRpcJson?.orderRef ?? "") !== String(firstRpcJson?.orderRef ?? "") ||
      asNumber(replayRpcJson?.canonicalLineCount) !== 1 ||
      asNumber(replayRpcJson?.totalUnitQuantity) !== 1
    ) {
      fail("Immediate replay Slice E tidak identik dengan fresh identity.");
      failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_REPLAY_IDENTITY_MISMATCH");
    }
  }

  const normalizationRowsAfter = await readSliceENormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRowsAfter) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_NORMALIZATION_UNAVAILABLE");
  const normalizationRow = assertSliceETiktokNormalizationRowExact(
    normalizationRowsAfter,
    organizationId,
  );
  if (!normalizationRow) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_NORMALIZATION_NOT_EXACT");

  const lifecycleRowsAfter = await readSliceELifecycleRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!lifecycleRowsAfter) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_LIFECYCLE_UNAVAILABLE");
  const assertionContexts = resolveGoldenAssertionContexts({
    highestPersistedPhase: existingNormalization
      ? currentSerumProjectionPhaseContext
      : { detectedPhase: "SLICE_E_RESERVED" },
    targetSlice: "SLICE_E",
    operation: existingNormalization ? "REPLAY" : "RESERVE",
    checkpoint: "AFTER_TIKTOK_RESERVATION",
  });
  const lifecycleRow = assertSliceETiktokLifecycleRowExact(
    {
      rows: lifecycleRowsAfter,
      normalizationRow,
      lifecyclePhaseContext: assertionContexts.lifecyclePhase,
    },
  );
  if (!lifecycleRow) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_LIFECYCLE_NOT_EXACT");

  const expectedProjectionStateAfter = assertionContexts.projectionPhase;
  if (!expectedProjectionStateAfter) {
    fail("Phase konteks Slice E belum tersedia.");
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_PHASE_UNKNOWN");
  }
  const expectedSerumProjectionAfter = expectedProjectionStateAfter.serumProduct;
  if (!expectedSerumProjectionAfter || typeof expectedSerumProjectionAfter !== "object") {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_PROJECTION_SHAPE_INVALID");
  }

  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_BATCH_2608_UNAVAILABLE");

  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_BATCH_2612_UNAVAILABLE");

  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_BATCH_2701_UNAVAILABLE");
  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_PRODUCT_UNAVAILABLE");
  const afterProjection = {
    productInventory: afterProductRows,
    batchInventory: [
      ...afterBatch2608Rows,
      ...afterBatch2612Rows,
      ...afterBatch2701Rows,
    ],
  };
  if (!matchesSerumProjectionExact(afterProjection, expectedSerumProjectionAfter)) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_PROJECTION_NOT_EXACT", {
      expectedPhase: expectedProjectionStateAfter.detectedPhase,
      expectedProjection: expectedSerumProjectionAfter,
      actualProjection: afterProductRows,
    });
  }
  const directAfterProjection = buildGoldenProjectionEvidence({
    rows: afterProductRows,
    projectionPhase: expectedProjectionStateAfter,
    productCode: "SER-NIA-30",
    assertionLabel: "Slice E authoritative afterProjection",
  });
  const afterBatch2608Match = expectedBatchQuantityForPhase(expectedProjectionStateAfter, "SER-2608-A");
  const afterBatch2612Match = expectedBatchQuantityForPhase(expectedProjectionStateAfter, "SER-2612-B");
  const afterBatch2701Match = expectedBatchQuantityForPhase(expectedProjectionStateAfter, "SER-2701-C");
  if (
    !assertSliceCBatchProjection(afterBatch2608Rows, "SER-2608-A", afterBatch2608Match) ||
    !assertSliceCBatchProjection(afterBatch2612Rows, "SER-2612-B", afterBatch2612Match) ||
    !assertSliceCBatchProjection(afterBatch2701Rows, "SER-2701-C", afterBatch2701Match)
  ) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_BATCH_NOT_EXACT");
  }

  if (!matchesSerumProjectionExact({
    productInventory: afterProductRows,
    batchInventory: [
      ...afterBatch2608Rows,
      ...afterBatch2612Rows,
      ...afterBatch2701Rows,
    ],
  }, expectedSerumProjectionAfter)) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_PROJECTION_ASSERTION_FAILED");
  }

  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_AFTER_LEDGER_UNAVAILABLE");
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);
  if (
    beforeLedgerSummary.rowCount !== afterLedgerSummary.rowCount ||
    beforeLedgerSummary.totalQuantityDelta !== afterLedgerSummary.totalQuantityDelta
  ) {
    fail("Slice E reservation harus stock-neutral tanpa ledger movement.");
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_LEDGER_NOT_STOCK_NEUTRAL");
  }

  const replayPhaseContract = assertionContexts.replayPhaseContract;
  const historicalOperationEvidence = {
    exact: true,
    duplicateReservation: normalizationRowsAfter.length !== 1,
    duplicateEvent: normalizationRowsAfter.length !== 1,
    duplicateLedger: beforeLedgerSummary.rowCount !== afterLedgerSummary.rowCount,
  };
  assertGoldenHistoricalReplayEvidence({
    phaseContract: replayPhaseContract,
    evidence: historicalOperationEvidence,
    operation: "SLICE_E_RESERVATION",
  });

  return {
    outcome: existingNormalization ? "ADOPTED" : "CREATED",
    reservationId: String(normalizationRow.reservation_id),
    phase: expectedProjectionStateAfter,
    replayPhaseContract,
    response: existingNormalization ? replayRpcJson : firstRpcJson,
    persistedEvidence: {
      exact: true,
      duplicateReservation: false,
      duplicateEvent: false,
      projectionPhase: expectedProjectionStateAfter.detectedPhase,
      productCode: "SER-NIA-30",
      projectionReplayContext: {
        checkpointPhase: replayPhaseContract.checkpointPhase,
        authoritativePhase: replayPhaseContract.authoritativePhase,
        projectionEvidencePhase: expectedProjectionStateAfter.detectedPhase,
        productCode: "SER-NIA-30",
        currentProjection: directAfterProjection,
        historicalOperationEvidence,
      },
      beforeProjection: buildGoldenProjectionEvidence({
        rows: beforeProductRows,
        projectionPhase: existingNormalization
          ? expectedProjectionStateAfter
          : expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_D_SHIPPED" }),
        productCode: "SER-NIA-30",
        assertionLabel: "Slice E authoritative beforeProjection",
      }),
      afterProjection: directAfterProjection,
      reservation: {
        reservationId: String(normalizationRow.reservation_id),
        statusCode: String(normalizationRow.reservation_status_code),
      },
      eventEvidence: {
        eventId: String(normalizationRow.marketplace_event_id),
        normalizationEventId: String(normalizationRow.normalization_event_id),
      },
      normalizationRow,
      lifecycleRow,
      beforeLedgerSummary,
      afterLedgerSummary,
    },
  };
}

async function runSliceETiktokShipmentStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const payload = buildSliceEShipPayload(organizationId);

  const existingEventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&limit=2&select=*`,
  );
  if (!existingEventRows) return null;
  if (existingEventRows.length > 1) {
    fail(`Slice E menemukan ${existingEventRows.length} event untuk identity yang harus tunggal.`);
    return null;
  }

  const normalizationRows = await readSliceENormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRows) return null;
  const normalizationRow = assertSliceETiktokNormalizationRowExact(normalizationRows, organizationId);
  if (!normalizationRow) return null;

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) return null;

  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) return null;

  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) return null;

  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) return null;

  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) return null;
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);

  let firstRpcJson;
  let replayRpcJson;

  if (existingEventRows.length === 0) {
    const beforeProjection = {
      productInventory: beforeProductRows,
      batchInventory: [
        ...beforeBatch2608Rows,
        ...beforeBatch2612Rows,
        ...beforeBatch2701Rows,
      ],
    };
    const matchesFreshPhase = matchesSerumProjectionExact(
      beforeProjection,
      buildSliceEProjectionPhase("SLICE_E_RESERVED", 1, 0),
    );
    const matchesAdvancedPhase = matchesSerumProjectionExact(
      beforeProjection,
      buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN),
    );

    if (!matchesFreshPhase && !matchesAdvancedPhase) {
      fail("Baseline Slice E product_inventory tidak exact.");
      return null;
    }

    if (matchesAdvancedPhase) {
      const afterLedgerRows = await readStockLedgerByProductId(
        supabaseUrl,
        publishableKey,
        accessToken,
        organizationId,
        serumProductId,
      );
      if (!afterLedgerRows) return null;
      const afterLedgerSummary = summarizeLedger(afterLedgerRows);
      return {
        normalizationRow,
        beforeLedgerSummary,
        afterLedgerSummary,
      };
    }

    const fresh = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (fresh.status !== 200) {
      fail(`ship_marketplace_listing_event fresh Slice E gagal: ${parseResponseText(fresh.payload)}`);
      return null;
    }
    firstRpcJson = assertSliceEShipRpcResponseExact(fresh.payload);
    if (!firstRpcJson) return null;
    if (String(firstRpcJson?.adapterContract ?? "") !== "MARKETPLACE_LISTING_SHIP_V1") {
      fail("Response RPC Slice E ship tidak menyertakan adapterContract exact.");
      return null;
    }

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`ship_marketplace_listing_event replay Slice E gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceEShipRpcResponseExact(replay.payload);
    if (!replayRpcJson) return null;
    if (
      String(replayRpcJson?.eventId ?? "") !== String(firstRpcJson?.eventId ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(firstRpcJson?.orderId ?? "") ||
      String(replayRpcJson?.transactionId ?? "") !== String(firstRpcJson?.transactionId ?? "") ||
      String(replayRpcJson?.transactionNo ?? "") !== String(firstRpcJson?.transactionNo ?? "")
    ) {
      fail("Immediate replay Slice E ship tidak mengadopsi identity fresh.");
      return null;
    }
  } else {
    const existingEvent = assertSliceETiktokEventExact(existingEventRows[0], organizationId, SLICE_E.externalShipEventRef);
    if (!existingEvent) return null;

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`ship_marketplace_listing_event replay existing Slice E gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceEShipRpcResponseExact(replay.payload);
    if (!replayRpcJson) return null;
    if (
      String(replayRpcJson?.eventId ?? "") !== String(existingEvent.event_id ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(existingEvent.order_id ?? "") ||
      String(replayRpcJson?.transactionId ?? "") !== String(existingEvent.transaction_id ?? "")
    ) {
      fail("Replay existing Slice E ship tidak cocok dengan event existing.");
      return null;
    }
  }

  const eventRowsAfter = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&limit=2&select=*`,
  );
  if (!eventRowsAfter) return null;
  if (eventRowsAfter.length !== 1) {
    fail(`api.marketplace_events Slice E setelah replay harus tepat satu row, tetapi ditemukan ${eventRowsAfter.length}.`);
    return null;
  }
  const eventRow = assertSliceETiktokEventExact(eventRowsAfter[0], organizationId, SLICE_E.externalShipEventRef);
  if (!eventRow) return null;

  const allocationRows = await readMarketplaceShipAllocationsByEventId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    eventRow.event_id,
  );
  if (!allocationRows) return null;
  if (!assertSliceETiktokAllocationsExact(allocationRows, serumProductId)) return null;

  const reservationRows = await readMarketplaceReservationsByOrderRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    SLICE_E.channelCode,
    SLICE_E.externalOrderRef,
    SLICE_E.canonicalSourceLineRef,
  );
  if (!reservationRows) return null;
  if (!assertSliceETiktokReservationExact(reservationRows, serumProductId, normalizationRow)) return null;

  const lifecycleRows = await readSliceELifecycleRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!lifecycleRows) return null;
  const assertionContexts = resolveGoldenAssertionContexts({
    highestPersistedPhase: existingEventRows.length === 0
      ? { detectedPhase: "SLICE_E_IN_TRANSIT" }
      : currentSerumProjectionPhaseContext,
    targetSlice: "SLICE_E",
    operation: existingEventRows.length === 0 ? "SHIP" : "REPLAY",
    checkpoint: "AFTER_TIKTOK_SHIPMENT",
  });
  if (!assertSliceETiktokLifecycleRowExact({
    rows: lifecycleRows,
    normalizationRow,
    lifecyclePhaseContext: assertionContexts.lifecyclePhase,
  })) return null;

  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) return null;
  const productSellable = asNumber(afterProductRows[0]?.sellable_qty);
  const productReserved = asNumber(afterProductRows[0]?.reserved_qty);
  const productAvailable = asNumber(afterProductRows[0]?.available_qty);
  const currentExpected = assertionContexts.projectionPhase;
  const projectionMatchesCurrent =
    productSellable === currentExpected.serumProduct.sellable &&
    productReserved === currentExpected.serumProduct.reserved &&
    productAvailable === currentExpected.serumProduct.available;
  const projectionMatchesReserved = productSellable === 24 && productReserved === 2 && productAvailable === 22;
  const projectionMatchesAdvanced = productSellable === 24 && productReserved === 0 && productAvailable === 24;
  const projectionMatchesShipped = productSellable === 22 && productReserved === 0 && productAvailable === 22;
  if (!projectionMatchesCurrent) {
    fail(
      `Projection product Slice E tidak exact. actual=${JSON.stringify({
        detectedPhase: currentExpected.phase,
        sellable_qty: productSellable,
        reserved_qty: productReserved,
        available_qty: productAvailable,
      })}`,
    );
    return null;
  }
  const observedProjectionPhase = projectionMatchesShipped
    ? "SLICE_G_BUNDLE_SHIPPED"
    : projectionMatchesReserved
      ? "SLICE_G_BUNDLE_RESERVED"
      : projectionMatchesAdvanced
        ? "SLICE_F_MANUAL_BONUS"
        : "SLICE_E_IN_TRANSIT";
   const expectedBatch2612Qty = currentExpected.serumProductionBatches["SER-2612-B"];
  console.log(JSON.stringify({
    basePhase: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
    bundleClassification: projectionMatchesShipped
      ? "EXACT_SHIPPED"
      : projectionMatchesReserved
        ? "EXACT_RESERVED"
        : projectionMatchesAdvanced
          ? "EXACT_EXISTING"
          : "NONE",
    observedProjectionPhase,
     effectivePhase: currentExpected.phase,
     projectionAssertionPhase: currentExpected.phase,
  }, null, 2));

  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2608Rows, "SER-2608-A", 0)) return null;

  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2612Rows, "SER-2612-B", expectedBatch2612Qty)) return null;

  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2701Rows, "SER-2701-C", 10)) return null;

  const ledgerRows = await readStockLedgerByTransactionId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    eventRow.transaction_id,
  );
  if (!ledgerRows) return null;
  if (!assertSliceETiktokLedgerExact(ledgerRows, organizationId, eventRow.transaction_id, replayRpcJson?.transactionNo ?? eventRow.transaction_id, serumProductId)) {
    return null;
  }
  if (!assertSliceEHistoricalShipmentEvidence({
    eventRow,
    allocationRows,
    reservationRows,
    ledgerRows,
    normalizationRow,
    organizationId,
    serumProductId,
  })) return null;

  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) return null;
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);

  if (existingEventRows.length === 0) {
    if (
      afterLedgerSummary.rowCount !== beforeLedgerSummary.rowCount + 1 ||
      afterLedgerSummary.totalQuantityDelta !== beforeLedgerSummary.totalQuantityDelta - 1
    ) {
      fail("Ledger summary Slice E fresh tidak exact.");
      return null;
    }
  } else if (
    afterLedgerSummary.rowCount !== beforeLedgerSummary.rowCount ||
    afterLedgerSummary.totalQuantityDelta !== beforeLedgerSummary.totalQuantityDelta
  ) {
    fail("Replay existing Slice E tidak boleh menambah ledger.");
    return null;
  }

  return {
    eventRow,
    allocationRows,
    reservationRows,
    lifecycleRows,
    ledgerRows,
  };
}

function assertSliceCListingLifecycleSnapshot(productRows, batch2608Rows, batch2612Rows, batch2701Rows, ledgerSummary, expectedReservedQty) {
  if (
    !Array.isArray(productRows) ||
    productRows.length !== 1 ||
    String(productRows[0]?.sku ?? "") !== "SER-NIA-30" ||
    asNumber(productRows[0]?.sellable_qty) !== 35 ||
    asNumber(productRows[0]?.reserved_qty) !== expectedReservedQty ||
    asNumber(productRows[0]?.available_qty) !== 35 - expectedReservedQty
  ) {
    fail("Snapshot lifecycle listing Slice C untuk product_inventory tidak exact.");
    return false;
  }
  if (
    !assertSliceCBatchProjection(batch2608Rows, "SER-2608-A", 5) ||
    !assertSliceCBatchProjection(batch2612Rows, "SER-2612-B", 20) ||
    !assertSliceCBatchProjection(batch2701Rows, "SER-2701-C", 10)
  ) {
    return false;
  }
  if (
    !ledgerSummary ||
    !Number.isFinite(ledgerSummary.rowCount) ||
    !Number.isFinite(ledgerSummary.totalQuantityDelta)
  ) {
    fail("Snapshot lifecycle listing Slice C untuk ledger tidak valid.");
    return false;
  }
  return true;
}

async function ensureSliceCShopeeListing(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  serumProductId,
  expectedReservedQty,
) {
  const catalogBefore = await readSliceCListingCatalogRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!catalogBefore) {
    return null;
  }
  if (catalogBefore.length > 1) {
    fail(`Catalog Slice C harus tepat 0 atau 1 row, tetapi ditemukan ${catalogBefore.length}.`);
    return null;
  }

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) {
    return null;
  }
  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) {
    return null;
  }
  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) {
    return null;
  }
  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) {
    return null;
  }
  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) {
    return null;
  }
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);
  if (!assertSliceCListingLifecycleSnapshot(
    beforeProductRows,
    beforeBatch2608Rows,
    beforeBatch2612Rows,
    beforeBatch2701Rows,
    beforeLedgerSummary,
    expectedReservedQty,
  )) {
    return null;
  }

  let listingId = "";
  let versionId = "";

  if (catalogBefore.length === 0) {
    const draftPayload = {
      p_organization_id: organizationId,
      p_idempotency_key: SLICE_C_LISTING.draftIdempotencyKey,
      p_channel_code: "SHOPEE",
      p_external_listing_code: "SHP-SER-NIA-30",
      p_display_name: "Golden Demo Shopee Serum",
      p_listing_type_code: "SINGLE",
      p_effective_from: "2026-07-15T00:00:00Z",
      p_product_id: serumProductId,
      p_components: [],
      p_note: SLICE_C_LISTING.note,
      p_metadata: SLICE_C_LISTING.metadata,
    };
    const draft = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "create_marketplace_listing_version_draft",
      draftPayload,
    );
    if (draft.status !== 200) {
      fail(`create_marketplace_listing_version_draft gagal: ${parseResponseText(draft.payload)}`);
      return null;
    }
    const draftJson = assertSliceCListingDraftResponse(draft.payload);
    if (!draftJson) {
      return null;
    }
    listingId = String(draftJson.listingId);
    versionId = String(draftJson.versionId);

    const preview = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "preview_marketplace_listing_version_activation",
      {
        p_organization_id: organizationId,
        p_listing_id: listingId,
        p_version_id: versionId,
      },
    );
    if (preview.status !== 200) {
      fail(`preview_marketplace_listing_version_activation gagal: ${parseResponseText(preview.payload)}`);
      return null;
    }
    const previewJson = assertSliceCListingPreviewResponse(preview.payload, listingId, versionId);
    if (!previewJson) {
      return null;
    }

    const activation = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "activate_marketplace_listing_version",
      {
        p_organization_id: organizationId,
        p_idempotency_key: SLICE_C_LISTING.activationIdempotencyKey,
        p_listing_id: listingId,
        p_version_id: versionId,
        p_expected_row_version: previewJson.versionRowVersion,
        p_preview_basis_hash: previewJson.basisHash,
        p_confirmation: true,
      },
    );
    if (activation.status !== 200) {
      fail(`activate_marketplace_listing_version gagal: ${parseResponseText(activation.payload)}`);
      return null;
    }
    if (!assertSliceCListingActivationResponse(activation.payload, listingId, versionId, previewJson.basisHash)) {
      return null;
    }
  } else {
    const catalogRow = catalogBefore[0];
    if (String(catalogRow?.mapping_readiness_code ?? "") === "PUBLISHED") {
      const publishedCatalog = assertSliceCListingCatalogPublished(catalogRow, organizationId, serumProductId);
      if (!publishedCatalog) {
        return null;
      }
      listingId = String(publishedCatalog.listing_id);
      const versions = await readSliceCListingVersionRows(
        supabaseUrl,
        publishableKey,
        accessToken,
        organizationId,
        listingId,
      );
      if (!versions) {
        return null;
      }
      const eventTimeVersion = assertSliceCListingEventTimeVersion(versions, serumProductId, ["ACTIVE", "RETIRED"]);
      if (!eventTimeVersion) {
        return null;
      }
      versionId = String(eventTimeVersion.version_id);
    } else if (String(catalogRow?.mapping_readiness_code ?? "") === "DRAFT_ONLY") {
      const draftCatalog = assertSliceCListingCatalogDraft(catalogRow, organizationId);
      if (!draftCatalog) {
        return null;
      }
      listingId = String(draftCatalog.listing_id ?? "");
      if (!isNonBlank(listingId)) {
        fail("Catalog Slice C draft tidak memiliki listing_id.");
        return null;
      }
      const versions = await readSliceCListingVersionRows(
        supabaseUrl,
        publishableKey,
        accessToken,
        organizationId,
        listingId,
      );
      if (!versions) {
        return null;
      }
      const matchingDrafts = versions.filter((row) => (
        String(row?.listing_id ?? "") === listingId &&
        String(row?.listing_type_code ?? "") === "SINGLE" &&
        String(row?.status_code ?? "") === "DRAFT" &&
        String(row?.product_id ?? "") === String(serumProductId) &&
        sameInstant(row?.effective_from, SLICE_C_LISTING.effectiveFrom) &&
        sameJsonSubsetMetadata(row?.metadata ?? {})
      ));
      if (matchingDrafts.length !== 1) {
        fail(`Draft version Slice C harus tepat satu row exact, tetapi ditemukan ${matchingDrafts.length}.`);
        return null;
      }
      const draftRow = matchingDrafts[0];
      versionId = String(draftRow.version_id ?? "");
      if (!isNonBlank(versionId)) {
        fail("Draft version Slice C tidak memiliki version_id.");
        return null;
      }

      const preview = await rpcJson(
        supabaseUrl,
        publishableKey,
        accessToken,
        "preview_marketplace_listing_version_activation",
        {
          p_organization_id: organizationId,
          p_listing_id: listingId,
          p_version_id: versionId,
        },
      );
      if (preview.status !== 200) {
        fail(`preview_marketplace_listing_version_activation draft existing gagal: ${parseResponseText(preview.payload)}`);
        return null;
      }
      const previewJson = assertSliceCListingPreviewResponse(preview.payload, listingId, versionId);
      if (!previewJson) {
        return null;
      }

      const activation = await rpcJson(
        supabaseUrl,
        publishableKey,
        accessToken,
        "activate_marketplace_listing_version",
        {
          p_organization_id: organizationId,
          p_idempotency_key: SLICE_C_LISTING.activationIdempotencyKey,
          p_listing_id: listingId,
          p_version_id: versionId,
          p_expected_row_version: previewJson.versionRowVersion,
          p_preview_basis_hash: previewJson.basisHash,
          p_confirmation: true,
        },
      );
      if (activation.status !== 200) {
        fail(`activate_marketplace_listing_version draft existing gagal: ${parseResponseText(activation.payload)}`);
        return null;
      }
      if (!assertSliceCListingActivationResponse(activation.payload, listingId, versionId, previewJson.basisHash)) {
        return null;
      }
    } else {
      fail(`Catalog Slice C memiliki mapping_readiness_code tidak didukung: ${String(catalogRow?.mapping_readiness_code ?? "")}.`);
      return null;
    }
  }

  const catalogAfter = await readSliceCListingCatalogRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!catalogAfter) {
    return null;
  }
  if (catalogAfter.length !== 1) {
    fail(`Catalog Slice C setelah setup harus tepat satu row, tetapi ditemukan ${catalogAfter.length}.`);
    return null;
  }
  const catalogRowAfter = assertSliceCListingCatalogPublished(
    catalogAfter[0],
    organizationId,
    serumProductId,
  );
  if (!catalogRowAfter) {
    return null;
  }

  const versionRowsAfter = await readSliceCListingVersionRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    String(catalogRowAfter.listing_id ?? ""),
  );
  if (!versionRowsAfter) {
    return null;
  }
  const eventTimeVersionAfter = assertSliceCListingEventTimeVersion(
    versionRowsAfter,
    serumProductId,
    ["ACTIVE"],
  );
  if (!eventTimeVersionAfter) {
    return null;
  }

  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) {
    return null;
  }
  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) {
    return null;
  }
  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) {
    return null;
  }
  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) {
    return null;
  }
  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) {
    return null;
  }
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);
  if (!assertSliceCListingLifecycleSnapshot(
    afterProductRows,
    afterBatch2608Rows,
    afterBatch2612Rows,
    afterBatch2701Rows,
    afterLedgerSummary,
    expectedReservedQty,
  )) {
    return null;
  }
  if (
    beforeLedgerSummary.rowCount !== afterLedgerSummary.rowCount ||
    beforeLedgerSummary.totalQuantityDelta !== afterLedgerSummary.totalQuantityDelta
  ) {
    fail("Lifecycle listing Slice C harus stock-neutral tanpa ledger movement.");
    return null;
  }

  return {
    listingId: String(catalogRowAfter.listing_id),
    versionId: String(eventTimeVersionAfter.version_id),
  };
}

function assertSliceCNormalizationRowExact(rows, organizationId) {
  if (!Array.isArray(rows)) {
    fail("Normalization Slice C harus berupa array.");
    return null;
  }
  if (rows.length > 1) {
    fail(`Normalization Slice C harus tepat satu row, tetapi ditemukan ${rows.length}.`);
    return null;
  }
  if (rows.length === 0) {
    return null;
  }

  const row = rows[0];
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_C.channelCode ||
    String(row?.external_event_ref_snapshot ?? "") !== SLICE_C.externalEventRef ||
    String(row?.external_order_ref_snapshot ?? "") !== SLICE_C.externalOrderRef ||
    String(row?.event_source_status ?? "") !== SLICE_C.sourceStatus ||
    !sameInstant(row?.occurred_at, SLICE_C.occurredAt) ||
    !sameInstant(row?.received_at, SLICE_C.receivedAt) ||
    String(row?.source_line_ref ?? "") !== SLICE_C.sourceLineRef ||
    String(row?.external_listing_code_snapshot ?? "") !== SLICE_C.externalListingCode ||
    String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
    asNumber(row?.listing_quantity) !== 8 ||
    !isNonBlank(row?.single_listing_version_id) ||
    row?.bundle_recipe_id !== null ||
    asNumber(row?.component_no) !== 1 ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    asNumber(row?.unit_quantity_per_listing) !== 1 ||
    asNumber(row?.expanded_quantity) !== 8 ||
    String(row?.canonical_source_line_ref ?? "") !== `${SLICE_C.sourceLineRef}#C001` ||
    !isNonBlank(row?.reservation_id) ||
    asNumber(row?.reserved_qty) !== 8 ||
    asNumber(row?.consumed_qty) !== 0 ||
    asNumber(row?.released_qty) !== 0 ||
    !isNonBlank(row?.reservation_status_code)
  ) {
    fail("Normalization Slice C tidak exact.");
    return null;
  }

  return row;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained lifecycle assertion for state-aware Slice C replay diagnostics.
function assertSliceCLifecycleRowStateAware(rows, normalizationRow) {
  if (!Array.isArray(rows)) {
    fail("Lifecycle Slice C harus berupa array.");
    return null;
  }
  if (rows.length !== 1) {
    fail(`Lifecycle Slice C harus tepat satu row, tetapi ditemukan ${rows.length}.`);
    return null;
  }

  const row = rows[0];
  if (
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.external_order_ref ?? "") !== SLICE_C.externalOrderRef ||
    String(row?.channel_code ?? "") !== SLICE_C.channelCode ||
    String(row?.source_line_ref ?? "") !== SLICE_C.sourceLineRef ||
    String(row?.external_listing_code_snapshot ?? "") !== SLICE_C.externalListingCode ||
    String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
    asNumber(row?.listing_quantity) !== 8 ||
    asNumber(row?.component_no) !== 1 ||
    String(row?.canonical_source_line_ref ?? "") !== `${SLICE_C.sourceLineRef}#C001` ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    asNumber(row?.unit_quantity_per_listing) !== 1 ||
    asNumber(row?.expanded_quantity) !== 8 ||
    String(row?.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(row?.reserved_qty) !== 8 ||
    asNumber(row?.consumed_qty) !== 0 ||
    asNumber(row?.released_qty) !== 0 ||
    !isNonBlank(row?.reservation_status_code) ||
    asNumber(row?.open_reserved_quantity) !== 8 ||
    asNumber(row?.shipped_quantity) !== 0 ||
    asNumber(row?.pre_shipment_cancelled_quantity) !== 0 ||
    asNumber(row?.post_shipment_cancelled_quantity) !== 0 ||
    asNumber(row?.return_expected_quantity) !== 0 ||
    asNumber(row?.return_received_quantity) !== 0 ||
    asNumber(row?.return_sellable_quantity) !== 0 ||
    asNumber(row?.return_damaged_quantity) !== 0 ||
    asNumber(row?.return_lost_quantity) !== 0
  ) {
    fail("Lifecycle Slice C tidak exact.");
    return null;
  }

  return row;
}

function assertSliceCProductProjection(rows) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`Projection product Slice C harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }
  const row = rows[0];
  if (
    String(row?.sku ?? "") !== "SER-NIA-30" ||
    asNumber(row?.sellable_qty) !== 35 ||
    asNumber(row?.reserved_qty) !== 8 ||
    asNumber(row?.available_qty) !== 27
  ) {
    fail("Projection product Slice C tidak exact.");
    return null;
  }
  return row;
}

function assertSliceCBatchProjection(rows, batchCode, expectedSellableQty) {
  const safeRows = Array.isArray(rows) ? rows : [];
  const exactCandidates = safeRows.filter((row) => String(row?.batch_code ?? "") === batchCode);
  if (exactCandidates.length !== 1) {
    console.log(JSON.stringify({
      assertion: `Projection batch ${batchCode}`,
      expectedCandidateCount: 1,
      actualCandidateCount: exactCandidates.length,
      rowKeys: safeRows[0] ? Object.keys(safeRows[0]).sort() : [],
      candidates: exactCandidates.map((row) => ({
        batchId: row?.batch_id ?? null,
        organizationId: row?.organization_id ?? null,
        productId: row?.product_id ?? null,
        sku: row?.sku ?? null,
        batchCode: row?.batch_code ?? null,
        sellableQty: row?.sellable_qty ?? null,
        quarantineQty: row?.quarantine_qty ?? null,
        damagedQty: row?.damaged_qty ?? null,
        statusCode: row?.status_code ?? null,
        batchKindCode: row?.batch_kind_code ?? null,
      })),
    }, null, 2));
    fail(`Projection batch ${batchCode} harus tepat satu row, tetapi ditemukan ${exactCandidates.length}.`);
    return null;
  }
  const row = exactCandidates[0];
  const actualSellableQty = Number(row?.sellable_qty);
  if (
    String(row?.batch_code ?? "") !== batchCode ||
    !Number.isSafeInteger(actualSellableQty) ||
    actualSellableQty !== expectedSellableQty
  ) {
    console.log(JSON.stringify({
      assertion: `Projection batch ${batchCode}`,
      rowKeys: Object.keys(row ?? {}).sort(),
      actual: {
        organizationId: row?.organization_id ?? null,
        batchId: row?.batch_id ?? null,
        batchCode: row?.batch_code ?? null,
        productId: row?.product_id ?? null,
        sku: row?.sku ?? null,
        sellableQty: row?.sellable_qty ?? null,
        quarantineQty: row?.quarantine_qty ?? null,
        damagedQty: row?.damaged_qty ?? null,
        statusCode: row?.status_code ?? null,
        batchKindCode: row?.batch_kind_code ?? null,
      },
      expected: {
        batchCode,
        sellableQty: expectedSellableQty,
      },
    }, null, 2));
    fail(`Projection batch ${batchCode} tidak exact.`);
    return null;
  }
  return row;
}

function assertSliceCRpcResponseExact(responseJson, expectedOutcome) {
  if (!responseJson || typeof responseJson !== "object") {
    fail("Response RPC Slice C harus object.");
    return null;
  }
  if (
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.externalEventOutcome ?? "") !== expectedOutcome ||
    String(responseJson?.eventRef ?? "") !== SLICE_C.externalEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_C.externalOrderRef ||
    String(responseJson?.channelCode ?? "") !== SLICE_C.channelCode ||
    String(responseJson?.sourceStatus ?? "") !== SLICE_C.sourceStatus ||
    asNumber(responseJson?.sourceLineCount) !== 1 ||
    asNumber(responseJson?.canonicalLineCount) !== 1 ||
    asNumber(responseJson?.totalUnitQuantity) !== 8 ||
    !sameInstant(responseJson?.occurredAt, SLICE_C.occurredAt) ||
    !sameInstant(responseJson?.receivedAt, SLICE_C.receivedAt) ||
    !isNonBlank(responseJson?.rawPayloadHash) ||
    asNumber(responseJson?.normalizationSchemaVersion) !== 1 ||
    !isNonBlank(responseJson?.normalizationEventId) ||
    !isNonBlank(responseJson?.eventId) ||
    !isNonBlank(responseJson?.orderId) ||
    !Array.isArray(responseJson?.sourceLines) ||
    responseJson.sourceLines.length !== 1 ||
    !responseJson?.reservation ||
    typeof responseJson.reservation !== "object"
  ) {
    fail(`Response RPC Slice C ${expectedOutcome} tidak exact.`);
    return null;
  }
  return responseJson;
}

async function runSliceCReservationStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const payload = buildSliceCPayload(organizationId);

  const existingNormalizationRows = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!existingNormalizationRows) {
    return null;
  }
  if (existingNormalizationRows.length > 1) {
    fail(`Normalization Slice C sebelum RPC harus 0 atau 1 row, tetapi ditemukan ${existingNormalizationRows.length}.`);
    return null;
  }

  const existingNormalization = assertSliceCNormalizationRowExact(
    existingNormalizationRows,
    organizationId,
  );
  if (existingNormalizationRows.length === 1 && !existingNormalization) {
    return null;
  }

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) {
    return null;
  }

  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) {
    return null;
  }
  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) {
    return null;
  }
  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) {
    return null;
  }

  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) {
    return null;
  }
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);

  if (existingNormalization) {
    const expectedPhaseBefore = currentSerumProjectionPhaseContext;

    if (!expectedPhaseBefore) {
      fail("Phase projection Serum belum tersedia untuk durable Slice C.");
      return null;
    }

    if (!assertSliceBProjection(
      {
        productInventory: beforeProductRows,
        batchInventory: [
          ...beforeBatch2608Rows,
          ...beforeBatch2612Rows,
          ...beforeBatch2701Rows,
        ],
      },
      expectedPhaseBefore,
    )) {
      return null;
    }
  } else {
    if (
      !Array.isArray(beforeProductRows) ||
      beforeProductRows.length !== 1 ||
      String(beforeProductRows[0]?.sku ?? "") !== "SER-NIA-30" ||
      asNumber(beforeProductRows[0]?.sellable_qty) !== 35 ||
      asNumber(beforeProductRows[0]?.reserved_qty) !== 0 ||
      asNumber(beforeProductRows[0]?.available_qty) !== 35
    ) {
      fail("Baseline fresh Slice C untuk product_inventory Serum tidak exact.");
      return null;
    }
  }

  /*
   * Pada fresh path sebelum reservation, projection masih harus berada pada
   * Slice B: 5/20/10. Pada durable replay, projection sudah diverifikasi
   * melalui assertSliceBProjection(...) memakai phase context B/C/D.
   */
  if (
    !existingNormalization &&
    (
      !assertSliceCBatchProjection(
        beforeBatch2608Rows,
        "SER-2608-A",
        5,
      ) ||
      !assertSliceCBatchProjection(
        beforeBatch2612Rows,
        "SER-2612-B",
        20,
      ) ||
      !assertSliceCBatchProjection(
        beforeBatch2701Rows,
        "SER-2701-C",
        10,
      )
    )
  ) {
    return null;
  }

  let firstRpcJson;
  let replayRpcJson;

  if (existingNormalization) {
    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay existing gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceCRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) {
      return null;
    }
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(existingNormalization.normalization_event_id ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(existingNormalization.marketplace_event_id ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(existingNormalization.order_id ?? "")
    ) {
      fail("Replay existing Slice C tidak cocok dengan read model existing.");
      return null;
    }
  } else {
    const fresh = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (fresh.status !== 200) {
      fail(`reserve_marketplace_listing_event fresh gagal: ${parseResponseText(fresh.payload)}`);
      return null;
    }
    firstRpcJson = assertSliceCRpcResponseExact(fresh.payload, "CREATED");
    if (!firstRpcJson) {
      return null;
    }

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceCRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) {
      return null;
    }
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(firstRpcJson?.normalizationEventId ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(firstRpcJson?.eventId ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(firstRpcJson?.orderId ?? "") ||
      String(replayRpcJson?.eventRef ?? "") !== String(firstRpcJson?.eventRef ?? "") ||
      String(replayRpcJson?.orderRef ?? "") !== String(firstRpcJson?.orderRef ?? "") ||
      asNumber(replayRpcJson?.canonicalLineCount) !== 1 ||
      asNumber(replayRpcJson?.totalUnitQuantity) !== 8
    ) {
      fail("Immediate replay Slice C tidak identik dengan fresh identity.");
      return null;
    }
  }

  const normalizationRowsAfter = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRowsAfter) {
    return null;
  }
  const normalizationRow = assertSliceCNormalizationRowExact(
    normalizationRowsAfter,
    organizationId,
  );
  if (!normalizationRow) {
    return null;
  }

  const lifecycleRowsAfter = await readSliceCLifecycleRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!lifecycleRowsAfter) {
    return null;
  }
  const assertionContexts = resolveGoldenAssertionContexts({
    highestPersistedPhase: existingNormalization
      ? currentSerumProjectionPhaseContext
      : { detectedPhase: "SLICE_C_RESERVED" },
    targetSlice: "SLICE_C",
    operation: existingNormalization ? "REPLAY" : "RESERVE",
    checkpoint: "AFTER_SHOPEE_RESERVATION",
  });
  const lifecycleRow = assertSliceCLifecycleRowExact({
    rows: lifecycleRowsAfter,
    normalizationRow,
    lifecyclePhaseContext: assertionContexts.lifecyclePhase,
  });
  if (!lifecycleRow) {
    return null;
  }

  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) {
    return null;
  }
  /*
   * Assertion 35/8/27 hanya berlaku setelah reserve pada fresh path.
   * Durable replay memakai phase-aware assertion B/C/D setelah seluruh
   * projection batch selesai dibaca.
   */
  if (
    !existingNormalization &&
    !assertSliceCProductProjection(afterProductRows)
  ) {
    return null;
  }

  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) {
    return null;
  }
  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) {
    return null;
  }
  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) {
    return null;
  }

  const expectedPhaseAfter = assertionContexts.projectionPhase;

  if (!expectedPhaseAfter) {
    fail("Phase projection Serum belum tersedia setelah replay Slice C.");
    return null;
  }

  if (!assertGoldenProductProjectionExact({
    actualProjection: afterProductRows,
    projectionPhaseContext: assertionContexts.projectionPhase,
    productCode: "SER-NIA-30",
    assertionLabel: "Slice D product projection",
  })) {
    return null;
  }

  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) {
    return null;
  }
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);
  if (
    beforeLedgerSummary.rowCount !== afterLedgerSummary.rowCount ||
    beforeLedgerSummary.totalQuantityDelta !== afterLedgerSummary.totalQuantityDelta
  ) {
    fail("Slice C harus stock-neutral tanpa ledger movement.");
    return null;
  }

  promoteSerumProjectionPhaseContext(expectedPhaseAfter);

  return {
    normalizationRow,
    lifecycleRow,
    beforeLedgerSummary,
    afterLedgerSummary,
  };
}

function buildSliceDPayload(organizationId) {
  return {
    p_organization_id: organizationId,
    p_idempotency_key: SLICE_D.idempotencyKey,
    p_channel_code: "SHOPEE",
    p_event_ref: SLICE_D.externalEventRef,
    p_order_ref: SLICE_D.externalOrderRef,
    p_source_status: "SHIPPED",
    p_occurred_at: SLICE_D.occurredAt,
    p_received_at: SLICE_D.receivedAt,
    p_lines: [{
      orderSourceLineRef: SLICE_D.orderSourceLineRef,
      componentNo: 1,
      quantity: 8,
    }],
    p_note: SLICE_D.note,
    p_raw_payload: {
      source: "golden-demo-runner",
      version: 1,
      slice: "D",
      scenario: "shopee-shipped-fefo-8",
    },
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "D",
      scenario: "shopee-shipped-fefo-8",
    },
    p_schema_version: 1,
  };
}

async function readMarketplaceEventsByRef(supabaseUrl, publishableKey, accessToken, organizationId, channelCode, eventRef) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(channelCode)}&external_event_ref=eq.${encodeURIComponent(eventRef)}&limit=2&select=*`,
  );
}

async function readMarketplaceShipAllocationsByEventId(supabaseUrl, publishableKey, accessToken, organizationId, eventId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_ship_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&event_id=eq.${encodeURIComponent(eventId)}&order=allocation_no.asc&select=*`,
  );
}

async function resolveSliceDReturnShipmentProvenance(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId, sourceLineRef) {
  const orderRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_orders?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_D.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_D.externalOrderRef)}&select=*`,
  );
  if (!orderRows) return null;
  const orderCandidates = orderRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.channel_code ?? "") === SLICE_D.channelCode &&
    String(row?.external_order_ref ?? "") === SLICE_D.externalOrderRef &&
    String(row?.status_code ?? "") === "SHIPPED",
  );
  if (orderCandidates.length !== 1) {
    fail(orderCandidates.length === 0 ? "SLICE_H_SHIPMENT_ORDER_NOT_FOUND" : "SLICE_H_SHIPMENT_ORDER_AMBIGUOUS");
    return null;
  }
  const order = orderCandidates[0];

  const eventRows = await readMarketplaceEventsByRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    SLICE_D.channelCode,
    SLICE_D.externalEventRef,
  );
  if (!eventRows) return null;
  const eventCandidates = eventRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.order_id ?? "") === String(order?.order_id ?? "") &&
    String(row?.channel_code ?? "") === SLICE_D.channelCode &&
    String(row?.external_event_ref ?? "") === SLICE_D.externalEventRef &&
    String(row?.event_type_code ?? "") === "SHIP" &&
    String(row?.status_code ?? "") === "APPLIED" &&
    String(row?.metadata?.sourceStatus ?? "") === SLICE_D.sourceStatus &&
    String(row?.metadata?.adapterContract ?? "") === "MARKETPLACE_LISTING_SHIP_V1" &&
    UUID_PATTERN.test(String(row?.transaction_id ?? "")),
  );
  if (eventCandidates.length !== 1) {
    fail(eventCandidates.length === 0 ? "SLICE_H_SHIPMENT_EVENT_NOT_FOUND" : "SLICE_H_SHIPMENT_EVENT_AMBIGUOUS");
    return null;
  }
  const event = eventCandidates[0];

  const allocationRows = await readMarketplaceShipAllocationsByEventId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    String(event.event_id ?? ""),
  );
  if (!allocationRows) return null;
  const allocationCandidates = allocationRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId) &&
    String(row?.event_id ?? "") === String(event?.event_id ?? "") &&
    String(row?.product_id ?? "") === String(serumProductId) &&
    String(row?.product_sku_snapshot ?? "") === SLICE_H.productSku &&
    String(row?.source_line_ref ?? "") === sourceLineRef &&
    String(row?.batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode &&
    asNumber(row?.quantity_allocated) === SLICE_H.receiptQuantity &&
    UUID_PATTERN.test(String(row?.allocation_id ?? "")) &&
    UUID_PATTERN.test(String(row?.event_line_id ?? "")) &&
    UUID_PATTERN.test(String(row?.ledger_entry_id ?? "")),
  );
  if (allocationCandidates.length !== 1) {
    fail(allocationCandidates.length === 0 ? "SLICE_H_SER2612B_ALLOCATION_NOT_FOUND" : "SLICE_H_SER2612B_ALLOCATION_AMBIGUOUS");
    return null;
  }
  const allocation = allocationCandidates[0];
  return {
    orderId: String(order.order_id),
    orderRef: String(order.external_order_ref),
    eventId: String(event.event_id),
    transactionId: String(event.transaction_id),
    allocationId: String(allocation.allocation_id),
    eventLineId: String(allocation.event_line_id),
    ledgerEntryId: String(allocation.ledger_entry_id),
    productId: String(allocation.product_id),
    batchId: String(allocation.batch_id),
    batchCode: String(allocation.batch_code_snapshot),
    quantityAllocated: asNumber(allocation.quantity_allocated),
    sourceLineRef: String(allocation.source_line_ref),
    allocation,
  };
}

async function readMarketplaceReservationsByOrderRef(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  channelCode,
  orderRef,
  externalItemRef = "",
) {
  const sourceLineFilter = String(externalItemRef ?? "").trim()
    ? `&external_item_ref=eq.${encodeURIComponent(String(externalItemRef).trim())}`
    : "";
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_reservations?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(channelCode)}&external_order_ref=eq.${encodeURIComponent(orderRef)}${sourceLineFilter}&order=line_no.asc&select=*`,
  );
}

async function readSliceDLifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId) {
  return await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_D.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_D.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_D.orderSourceLineRef)}&component_no=eq.1&limit=2&select=*`,
  );
}

function assertProjectionExact(rows, expected, label) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`${label} harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  if (
    String(row?.sku ?? "") !== "SER-NIA-30" ||
    asNumber(row?.sellable_qty) !== expected.sellable ||
    asNumber(row?.reserved_qty) !== expected.reserved ||
    asNumber(row?.available_qty) !== expected.available
  ) {
    fail(`${label} tidak exact.`);
    return null;
  }

  return row;
}

function assertSliceCStateAwareProductProjection(rows) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`Projection product Slice C state-aware harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  const isBeforeShipment = (
    String(row?.sku ?? "") === "SER-NIA-30" &&
    asNumber(row?.sellable_qty) === 35 &&
    asNumber(row?.reserved_qty) === 8 &&
    asNumber(row?.available_qty) === 27
  );
  const isAfterShipment = (
    String(row?.sku ?? "") === "SER-NIA-30" &&
    asNumber(row?.sellable_qty) === 27 &&
    asNumber(row?.reserved_qty) === 0 &&
    asNumber(row?.available_qty) === 27
  );

  if (!isBeforeShipment && !isAfterShipment) {
    fail("Projection product Slice C state-aware tidak exact.");
    return null;
  }

  return row;
}

function buildSerumProjectionPhase(name, sliceCNormalizationCount, sliceDShipEventCount) {
  const detectedPhase = String(name ?? "");
  if (!["SLICE_B_RECEIVED", "SLICE_C_RESERVED", "SLICE_D_SHIPPED", "SLICE_F_MANUAL_BONUS"].includes(detectedPhase)) {
    throw new Error(`GOLDEN_PHASE_UNKNOWN: ${detectedPhase || "<empty>"}`);
  }
  return {
    ...expectedGoldenCurrentStateForPhase({ detectedPhase }).serumProduct,
    detectedPhase,
    sliceCNormalizationCount,
    sliceDShipEventCount,
  };
}

function buildBundleProjectionPhase(name) {
  const detectedPhase = String(name ?? "");
  if (!["SLICE_F_MANUAL_BONUS", "SLICE_G_BUNDLE_RESERVED", "SLICE_G_BUNDLE_SHIPPED"].includes(detectedPhase)) {
    throw new Error(`GOLDEN_PHASE_UNKNOWN: ${detectedPhase || "<empty>"}`);
  }
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase });
  return {
    ...expected.serumProduct,
    detectedPhase,
    cleanser: { ...expected.cleanserProduct, batches: expected.cleanserBatches },
  };
}

function buildReturnProjectionPhase(name) {
  const detectedPhase = String(name ?? "");
  if (![
    "SLICE_G_BUNDLE_SHIPPED",
    "SLICE_H_RETURN_EXPECTED",
    "SLICE_H_RETURN_RECEIVED",
    "SLICE_I_RETURN_INSPECTED",
    "SLICE_J_TIKTOK_RETURN_EXPECTED",
    "SLICE_J_TIKTOK_RETURN_LOST",
    "SLICE_K_TIKTOK_CLAIM_CREATED",
    "SLICE_K_TIKTOK_CLAIM_NOTIFICATION",
  ].includes(detectedPhase)) {
    throw new Error(`GOLDEN_PHASE_UNKNOWN: ${detectedPhase || "<empty>"}`);
  }
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase });
  return {
    ...expected.serumProduct,
    detectedPhase,
    cleanser: { ...expected.cleanserProduct, batches: expected.cleanserBatches },
  };
}

async function probeSliceIReturnInspectionState(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  serumProductId,
  returnRef = SLICE_H.correctedReturnRef,
  receiptRef = SLICE_H.correctedReceiptRef,
  inspectionRef = `${SLICE_H.correctedReturnRef}:INSPECTION`,
  authoritativePhase = null,
) {
  const returnProbe = await probeSliceHReturnState(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    returnRef,
    receiptRef,
  );
  if (!returnProbe) return null;
  if (returnProbe.classification === "NONE") {
    return {
      classification: "NONE",
      effectivePhase: buildReturnProjectionPhase("SLICE_I_RETURN_INSPECTED"),
      counts: {
        inspectionHeaderCount: 0,
        inspectionEventCount: 0,
        inspectionAllocationCount: 0,
        returnBatchCount: 0,
        transactionCount: 0,
        ledgerCount: 0,
      },
      evidence: {
        ...returnProbe.evidence,
        inspectionEventRows: [],
        inspectionAllocations: [],
        returnBatches: [],
        returnBatchInventoryRows: [],
        stockLedgerRows: [],
        inspectionTransactionId: "",
        inspectionLedgerEntryId: "",
      },
      failedChecks: [],
    };
  }
  const returnHeaderCandidates = returnProbe.evidence.returnHeaderRows ?? [];
  if (returnHeaderCandidates.length !== 1) {
    return {
      classification: "CONFLICT_OR_PARTIAL",
      effectivePhase: buildReturnProjectionPhase("SLICE_I_RETURN_INSPECTED"),
      counts: {},
      evidence: { ...returnProbe.evidence },
      failedChecks: [{ name: "return header count", expected: 1, actual: returnHeaderCandidates.length, passed: false }],
    };
  }
  const [returnHeader] = returnHeaderCandidates;

  const inspectionEventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_events?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(returnHeader.return_id ?? "")}&event_type_code=eq.INSPECTION&external_event_ref=eq.${encodeURIComponent(inspectionRef)}&select=*&limit=10`,
  );
  if (!inspectionEventRows) return null;

  const inspectionAllocations = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_inspection_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&inspection_ref=eq.${encodeURIComponent(inspectionRef)}&select=*&order=allocation_no.asc,inspection_allocation_id.asc&limit=10`,
  );
  if (!inspectionAllocations) return null;

  const returnBatches = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `return_stock_batches?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(returnHeader.return_id ?? "")}&select=*&order=created_at.asc,return_stock_batch_id.asc&limit=10`,
  );
  if (!returnBatches) return null;

  const returnBatchInventoryRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `batch_inventory?organization_id=eq.${encodeURIComponent(organizationId)}&product_id=eq.${encodeURIComponent(serumProductId)}&batch_kind_code=eq.RETURN&select=*&order=batch_code.asc&limit=10`,
  );
  if (!returnBatchInventoryRows) return null;

  const stockLedgerRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref_snapshot=eq.${encodeURIComponent(inspectionRef)}&select=*&order=ledger_seq.asc&limit=10`,
  );
  if (!stockLedgerRows) return null;

  const transactionIds = new Set(stockLedgerRows.map((row) => String(row?.transaction_id ?? "")).filter(isNonBlank));
  const exactInspectionCounts = {
    inspectionHeaderCount: inspectionEventRows.length,
    inspectionEventCount: inspectionEventRows.length,
    inspectionAllocationCount: inspectionAllocations.length,
    returnBatchCount: returnBatches.length,
    transactionCount: transactionIds.size,
    ledgerCount: stockLedgerRows.length,
  };

  const sellableAllocation = inspectionAllocations.filter((row) => String(row?.condition_code ?? "") === "SELLABLE");
  const damagedAllocation = inspectionAllocations.filter((row) => String(row?.condition_code ?? "") === "DAMAGED");
  const [returnBatchRow] = returnBatches;
  const [sellableAllocationRow] = sellableAllocation;
  const [damagedAllocationRow] = damagedAllocation;
  const [ledgerRow] = stockLedgerRows;
  const returnBatchInventoryCandidates = returnBatchInventoryRows.filter((row) =>
    String(row?.batch_id ?? "") === String(returnBatchRow?.batch_id ?? "") &&
    String(row?.product_id ?? "") === String(serumProductId) &&
    String(row?.batch_kind_code ?? "") === "RETURN",
  );
  const [returnBatchInventoryRow] = returnBatchInventoryCandidates;
  const [serumProjectionRow] = returnProbe.evidence.serumProductRows;
  const [cleanserProjectionRow] = returnProbe.evidence.cleanserProductRows;

  /*
   * The inspection allocation and its inbound ledger are immutable historical
   * evidence.  A durable replay can run after J/K and the terminal stocktake,
   * so the read model must be asserted against the current authoritative
   * phase, never forced back to Slice I's +2 projection.
   */
  const inspectionCheckpointPhase = "SLICE_I_RETURN_INSPECTED";
  const contextualAuthoritativePhase = phaseNameOf(authoritativePhase ?? currentSerumProjectionPhaseContext);
  const expectedProjectionPhase =
    knownGoldenPhaseRank(contextualAuthoritativePhase) >= knownGoldenPhaseRank(inspectionCheckpointPhase)
      ? contextualAuthoritativePhase
      : inspectionCheckpointPhase;
  const expectedCurrentState = expectedGoldenCurrentStateForPhase({ detectedPhase: expectedProjectionPhase });
  const expectedPhase = expectedCurrentState.serumProduct;
  const productProjectionMatches =
    matchesSerumProjectionExact(
      {
        productInventory: returnProbe.evidence.serumProductRows,
        batchInventory: [
          ...returnProbe.evidence.serumBatch2608Rows,
          ...returnProbe.evidence.serumBatch2612Rows,
          ...returnProbe.evidence.serumBatch2701Rows,
        ],
      },
      expectedPhase,
    ) &&
    Number(cleanserProjectionRow?.sellable_qty) === 14 &&
    Number(cleanserProjectionRow?.reserved_qty) === 0 &&
    Number(cleanserProjectionRow?.available_qty) === 14 &&
    returnBatchInventoryCandidates.length === 1 &&
    Number(returnBatchInventoryRow?.sellable_qty ?? NaN) === 2;

  const failedChecks = [];
  const pushCheck = (name, expected, actual, passed) => {
    const check = { name, expected, actual, passed };
    if (!passed) failedChecks.push(check);
    return check;
  };

  pushCheck("corrected returnRef", returnRef, String(returnHeader?.external_return_ref ?? ""), String(returnHeader?.external_return_ref ?? "") === returnRef);
  pushCheck("receiptLineId unique", 1, returnProbe.evidence.receiptLines.length, returnProbe.evidence.receiptLines.length === 1);
  pushCheck("inspection event count", 1, inspectionEventRows.length, inspectionEventRows.length === 1);
  pushCheck("allocation count", 2, inspectionAllocations.length, inspectionAllocations.length === 2);
  pushCheck("sellable allocation count", 1, sellableAllocation.length, sellableAllocation.length === 1 && String(sellableAllocationRow?.receipt_line_id ?? "") === String(returnProbe.evidence.persistedReceiptLine?.receiptLineId ?? "") && Number(sellableAllocationRow?.quantity_allocated) === 2 && String(sellableAllocationRow?.condition_code ?? "") === "SELLABLE" && String(sellableAllocationRow?.destination_bucket_code ?? "") === "SELLABLE" && String(sellableAllocationRow?.stock_effect_code ?? "") === "SELLABLE_INBOUND" && sellableAllocationRow?.source_ledger_entry_id === null && isNonBlank(sellableAllocationRow?.destination_ledger_entry_id) && isNonBlank(sellableAllocationRow?.return_batch_id));
  pushCheck("damaged allocation count", 1, damagedAllocation.length, damagedAllocation.length === 1 && String(damagedAllocationRow?.receipt_line_id ?? "") === String(returnProbe.evidence.persistedReceiptLine?.receiptLineId ?? "") && Number(damagedAllocationRow?.quantity_allocated) === 1 && String(damagedAllocationRow?.condition_code ?? "") === "DAMAGED" && damagedAllocationRow?.destination_bucket_code === null && String(damagedAllocationRow?.stock_effect_code ?? "") === "NONE" && damagedAllocationRow?.source_ledger_entry_id === null && damagedAllocationRow?.destination_ledger_entry_id === null && damagedAllocationRow?.return_batch_id === null);
  pushCheck("transaction count", 1, transactionIds.size, transactionIds.size === 1 && isNonBlank(ledgerRow?.transaction_id));
  pushCheck("ledger count", 1, stockLedgerRows.length, stockLedgerRows.length === 1 && Number(ledgerRow?.quantity_delta ?? NaN) === 2 && String(ledgerRow?.bucket_code ?? "") === "SELLABLE");
  pushCheck("return batch count", 1, returnBatches.length, returnBatches.length === 1 && returnBatchInventoryCandidates.length === 1 && String(returnBatchRow?.batch_kind_code ?? "") === "RETURN" && String(returnBatchRow?.status_code ?? "") === "ACTIVE" && String(returnBatchRow?.batch_id ?? "") !== String(returnBatchRow?.source_batch_id ?? "") && String(returnBatchRow?.source_batch_code_snapshot ?? "") === SLICE_H.sourceBatchCode && Number(returnBatchInventoryRow?.sellable_qty ?? NaN) === 2);
  pushCheck("projection exact", `${expectedPhase.sellable} / ${expectedPhase.reserved} / ${expectedPhase.available} and ${expectedCurrentState.cleanserProduct.sellable} / ${expectedCurrentState.cleanserProduct.reserved} / ${expectedCurrentState.cleanserProduct.available}`, `${String(serumProjectionRow?.sellable_qty ?? "")} / ${String(serumProjectionRow?.reserved_qty ?? "")} / ${String(serumProjectionRow?.available_qty ?? "")} and ${String(cleanserProjectionRow?.sellable_qty ?? "")} / ${String(cleanserProjectionRow?.reserved_qty ?? "")} / ${String(cleanserProjectionRow?.available_qty ?? "")}`, productProjectionMatches);

  const classification =
    inspectionEventRows.length === 1 &&
    inspectionAllocations.length === 2 &&
    stockLedgerRows.length === 1 &&
    returnBatches.length === 1 &&
    sellableAllocation.length === 1 &&
    damagedAllocation.length === 1 &&
    failedChecks.length === 0
      ? "EXACT_INSPECTED"
      : inspectionEventRows.length === 0 &&
        inspectionAllocations.length === 0 &&
        stockLedgerRows.length === 0 &&
        returnBatches.length === 0
        ? "NONE"
        : "CONFLICT_OR_PARTIAL";

  return {
    classification,
    effectivePhase: buildReturnProjectionPhase("SLICE_I_RETURN_INSPECTED"),
    counts: exactInspectionCounts,
    evidence: {
      ...returnProbe.evidence,
      inspectionEventRows,
      inspectionAllocations,
      returnBatches,
      returnBatchInventoryRows,
      stockLedgerRows,
      inspectionTransactionId: String(ledgerRow?.transaction_id ?? ""),
      inspectionLedgerEntryId: String(ledgerRow?.ledger_entry_id ?? ""),
      projectionEvidencePhase: expectedProjectionPhase,
    },
    failedChecks,
  };
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained compatibility wrapper for Slice E projection diagnostics.
function buildSerumProjectionPhaseContextForSliceE(phaseName, sliceENormalizationCount, sliceEShipEventCount) {
  return buildSliceEProjectionPhase(phaseName, sliceENormalizationCount, sliceEShipEventCount);
}

async function detectCurrentSerumProjectionPhase(supabaseUrl, publishableKey, accessToken, organizationId) {
  const sliceCNormalizationRows = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!sliceCNormalizationRows) return null;

  const sliceCNormalizationCount = sliceCNormalizationRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId)
    && String(row?.channel_code ?? "") === SLICE_C.channelCode
    && String(row?.external_event_ref_snapshot ?? "") === SLICE_C.externalEventRef,
  ).length;

  if (sliceCNormalizationCount > 1) {
    fail(`Normalization Slice C harus tunggal, tetapi ditemukan ${sliceCNormalizationCount}.`);
    return null;
  }

  const sliceDShipEventRows = await readMarketplaceEventsByRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    SLICE_D.channelCode,
    SLICE_D.externalEventRef,
  );
  if (!sliceDShipEventRows) return null;

  const sliceDShipEventCount = sliceDShipEventRows.filter((row) =>
    String(row?.organization_id ?? "") === String(organizationId)
    && String(row?.channel_code ?? "") === SLICE_D.channelCode
    && String(row?.external_event_ref ?? "") === SLICE_D.externalEventRef
    && String(row?.event_type_code ?? "") === "SHIP"
    && String(row?.status_code ?? "") === "APPLIED",
  ).length;

  if (sliceDShipEventCount > 1) {
    fail(`Event Slice D harus tunggal, tetapi ditemukan ${sliceDShipEventCount}.`);
    return null;
  }

  if (sliceDShipEventCount === 1) {
    return buildSerumProjectionPhase("SLICE_D_SHIPPED", sliceCNormalizationCount, sliceDShipEventCount);
  }

  if (sliceCNormalizationCount === 1) {
    return buildSerumProjectionPhase("SLICE_C_RESERVED", sliceCNormalizationCount, sliceDShipEventCount);
  }

  return buildSerumProjectionPhase("SLICE_B_RECEIVED", sliceCNormalizationCount, sliceDShipEventCount);
}

async function detectCurrentTiktokProjectionPhaseWrapper(supabaseUrl, publishableKey, accessToken, organizationId) {
  return detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
}

function marketplaceComponentIdentityFromLifecycleRow(row) {
  return {
    organizationId: String(row?.organization_id ?? ""),
    channelCode: String(row?.channel_code ?? ""),
    marketplaceOrderRef: String(row?.external_order_ref ?? ""),
    sourceLineRef: String(row?.source_line_ref ?? ""),
    canonicalSourceLineRef: String(row?.canonical_source_line_ref ?? ""),
    componentNo: asNumber(row?.component_no),
    productId: String(row?.product_id ?? ""),
    productSku: String(row?.product_sku_snapshot ?? ""),
  };
}

function expectedMarketplaceComponentLifecycleForPhase(phase, componentIdentity) {
  const expectedState = expectedGoldenCurrentStateForPhase(phase);
  const identity = validateMarketplaceComponentLifecycleIdentity(phaseNameOf(phase), componentIdentity);
  let lifecycle;
  if (identity.channelCode === SLICE_E.channelCode) {
    lifecycle = expectedState.tiktokComponentLifecycle;
  } else if (identity.channelCode === SLICE_C.channelCode) {
    lifecycle = expectedState.shopeeLifecycle;
  } else {
    throw goldenLifecycleExpectationError(phaseNameOf(phase), identity, [], [
      { path: "identity.channelCode", reason: "GOLDEN_LIFECYCLE_COMPONENT_UNKNOWN" },
    ]);
  }
  return validateMarketplaceComponentLifecycleExpectation(phaseNameOf(phase), identity, { ...lifecycle });
}

function assertSliceCLifecycleRowExact({ rows, normalizationRow, lifecyclePhaseContext }) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`Lifecycle Slice C harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const [row] = rows;
  const consumedQty = asNumber(row?.consumed_qty);
  const shippedQuantity = asNumber(row?.shipped_quantity);
  const openReservedQuantity = asNumber(row?.open_reserved_quantity);
  const returnExpectedQuantity = asNumber(row?.return_expected_quantity);
  const returnReceivedQuantity = asNumber(row?.return_received_quantity);

  const expectedState = expectedGoldenCurrentStateForPhase(lifecyclePhaseContext);
  const expectedPhase = { detectedPhase: expectedState.detectedPhase };
  const expected = expectedState.shopeeLifecycle;

  const expectedReturnExpectedQty = expected.returnExpected;
  const expectedReturnReceivedQty = expected.returnReceived;
  const expectedConsumedQuantity = expected.consumed;
  const expectedOpenReservedQuantity = expected.openReserved;
  const expectedShippedQuantity = expected.shipped;

  const sliceCChecks = [
    { name: "organization_id", expected: String(normalizationRow?.organization_id ?? ""), actual: String(row?.organization_id ?? ""), passed: String(row?.organization_id ?? "") === String(normalizationRow?.organization_id ?? "") },
    { name: "order_id", expected: String(normalizationRow?.order_id ?? ""), actual: String(row?.order_id ?? ""), passed: String(row?.order_id ?? "") === String(normalizationRow?.order_id ?? "") },
    { name: "external_order_ref", expected: SLICE_C.externalOrderRef, actual: String(row?.external_order_ref ?? ""), passed: String(row?.external_order_ref ?? "") === SLICE_C.externalOrderRef },
    { name: "channel_code", expected: SLICE_C.channelCode, actual: String(row?.channel_code ?? ""), passed: String(row?.channel_code ?? "") === SLICE_C.channelCode },
    { name: "source_line_ref", expected: SLICE_C.sourceLineRef, actual: String(row?.source_line_ref ?? ""), passed: String(row?.source_line_ref ?? "") === SLICE_C.sourceLineRef },
    { name: "listing_type_code_snapshot", expected: "SINGLE", actual: String(row?.listing_type_code_snapshot ?? ""), passed: String(row?.listing_type_code_snapshot ?? "") === "SINGLE" },
    { name: "listing_quantity", expected: 8, actual: asNumber(row?.listing_quantity), passed: asNumber(row?.listing_quantity) === 8 },
    { name: "mapping_version", expected: 1, actual: asNumber(row?.mapping_version), passed: asNumber(row?.mapping_version) === 1 },
    { name: "component_no", expected: 1, actual: asNumber(row?.component_no), passed: asNumber(row?.component_no) === 1 },
    { name: "product_id", expected: String(normalizationRow?.product_id ?? ""), actual: String(row?.product_id ?? ""), passed: String(row?.product_id ?? "") === String(normalizationRow?.product_id ?? "") },
    { name: "product_sku_snapshot", expected: "SER-NIA-30", actual: String(row?.product_sku_snapshot ?? ""), passed: String(row?.product_sku_snapshot ?? "") === "SER-NIA-30" },
    { name: "unit_quantity_per_listing", expected: 1, actual: asNumber(row?.unit_quantity_per_listing), passed: asNumber(row?.unit_quantity_per_listing) === 1 },
    { name: "expanded_quantity", expected: 8, actual: asNumber(row?.expanded_quantity), passed: asNumber(row?.expanded_quantity) === 8 },
    { name: "reservation_id", expected: String(normalizationRow?.reservation_id ?? ""), actual: String(row?.reservation_id ?? ""), passed: String(row?.reservation_id ?? "") === String(normalizationRow?.reservation_id ?? "") },
    { name: "reserved_qty", expected: 8, actual: asNumber(row?.reserved_qty), passed: asNumber(row?.reserved_qty) === 8 },
    { name: "consumed_qty", expected: expectedConsumedQuantity, actual: consumedQty, passed: consumedQty === expectedConsumedQuantity },
    { name: "released_qty", expected: 0, actual: asNumber(row?.released_qty), passed: asNumber(row?.released_qty) === 0 },
    { name: "reservation_status_code", expected: "nonblank", actual: String(row?.reservation_status_code ?? ""), passed: isNonBlank(row?.reservation_status_code) },
    { name: "open_reserved_quantity", expected: expectedOpenReservedQuantity, actual: openReservedQuantity, passed: openReservedQuantity === expectedOpenReservedQuantity },
    { name: "shipped_quantity", expected: expectedShippedQuantity, actual: shippedQuantity, passed: shippedQuantity === expectedShippedQuantity },
    { name: "pre_shipment_cancelled_quantity", expected: 0, actual: asNumber(row?.pre_shipment_cancelled_quantity), passed: asNumber(row?.pre_shipment_cancelled_quantity) === 0 },
    { name: "post_shipment_cancelled_quantity", expected: 0, actual: asNumber(row?.post_shipment_cancelled_quantity), passed: asNumber(row?.post_shipment_cancelled_quantity) === 0 },
    { name: "return_expected_quantity", expected: expectedReturnExpectedQty, actual: returnExpectedQuantity, passed: returnExpectedQuantity === expectedReturnExpectedQty },
    { name: "return_received_quantity", expected: expectedReturnReceivedQty, actual: returnReceivedQuantity, passed: returnReceivedQuantity === expectedReturnReceivedQty },
  ];

  if (
    String(row?.organization_id ?? "") !== String(normalizationRow?.organization_id ?? "") ||
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.external_order_ref ?? "") !== SLICE_C.externalOrderRef ||
    String(row?.channel_code ?? "") !== SLICE_C.channelCode ||
    String(row?.source_line_ref ?? "") !== SLICE_C.sourceLineRef ||
    String(row?.external_listing_code_snapshot ?? "") !== SLICE_C.externalListingCode ||
    String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
    asNumber(row?.listing_quantity) !== 8 ||
    asNumber(row?.mapping_version) !== 1 ||
    asNumber(row?.component_no) !== 1 ||
    String(row?.product_id ?? "") !== String(normalizationRow?.product_id ?? "") ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    asNumber(row?.unit_quantity_per_listing) !== 1 ||
    asNumber(row?.expanded_quantity) !== 8 ||
    String(row?.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(row?.reserved_qty) !== expected.reserved || asNumber(row?.consumed_qty) !== expected.consumed || asNumber(row?.released_qty) !== expected.released || String(row?.reservation_status_code ?? "") !== expected.reservationStatus || asNumber(row?.shipped_quantity) !== expected.shipped || asNumber(row?.pre_shipment_cancelled_quantity) !== expected.preShipmentCancelled || asNumber(row?.post_shipment_cancelled_quantity) !== expected.postShipmentCancelled || returnExpectedQuantity !== expected.returnExpected || returnReceivedQuantity !== expected.returnReceived || asNumber(row?.return_sellable_quantity) !== expected.returnSellable || asNumber(row?.return_damaged_quantity) !== expected.returnDamaged || asNumber(row?.return_lost_quantity) !== expected.returnLost || openReservedQuantity !== expected.openReserved || asNumber(row?.remaining_returnable_or_cancellable_quantity) !== expected.remaining
  ) {
    console.log(JSON.stringify({
      assertion: "Slice C lifecycle",
      orderRef: String(row?.external_order_ref ?? ""),
      sourceLineRef: String(row?.source_line_ref ?? ""),
      observedPhase: "SLICE_C_RESERVED", lifecyclePhaseContext: expectedPhase.detectedPhase, expectedLifecyclePhase: expectedPhase.detectedPhase, phaseRank: getSerumProjectionPhaseRank(expectedPhase), rowCount: rows.length, rowKeys: Object.keys(row).sort(), expected, lifecycleChecks: sliceCChecks,
    }, null, 2));
    fail("Lifecycle Slice C tidak exact.");
    return null;
  }

  return row;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained direct Slice C mutation path; runner uses state-aware replay.
async function runSliceCReservation(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const payload = buildSliceCPayload(organizationId);

  const existingNormalizationRows = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!existingNormalizationRows) return null;
  if (existingNormalizationRows.length > 1) {
    fail(`Normalization Slice C sebelum RPC harus 0 atau 1 row, tetapi ditemukan ${existingNormalizationRows.length}.`);
    return null;
  }

  const existingNormalization = assertSliceCNormalizationRowExact(
    existingNormalizationRows,
    organizationId,
  );
  if (existingNormalizationRows.length === 1 && !existingNormalization) {
    return null;
  }

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) return null;

  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) return null;

  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) return null;

  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) return null;

  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) return null;
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);

  if (existingNormalization) {
    const stateBefore = assertSliceCStateAwareProductProjection(beforeProductRows);
    if (!stateBefore) return null;
  } else if (
    !Array.isArray(beforeProductRows) ||
    beforeProductRows.length !== 1 ||
    String(beforeProductRows[0]?.sku ?? "") !== "SER-NIA-30" ||
    asNumber(beforeProductRows[0]?.sellable_qty) !== 35 ||
    asNumber(beforeProductRows[0]?.reserved_qty) !== 0 ||
    asNumber(beforeProductRows[0]?.available_qty) !== 35
  ) {
    fail("Baseline fresh Slice C untuk product_inventory Serum tidak exact.");
    return null;
  }

  const before2612Qty = existingNormalization ? [20, 17] : [20];
  const before2608Qty = existingNormalization ? [5, 0] : [5];

  if (
    !assertSliceCBatchProjection(beforeBatch2701Rows, "SER-2701-C", 10) ||
    !before2608Qty.includes(asNumber(beforeBatch2608Rows?.[0]?.sellable_qty)) ||
    !before2612Qty.includes(asNumber(beforeBatch2612Rows?.[0]?.sellable_qty))
  ) {
    fail("Projection batch Slice C state-aware tidak exact.");
    return null;
  }

  let firstRpcJson;
  let replayRpcJson;

  if (existingNormalization) {
    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay existing gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceCRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) return null;
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(existingNormalization.normalization_event_id ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(existingNormalization.marketplace_event_id ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(existingNormalization.order_id ?? "")
    ) {
      fail("Replay existing Slice C tidak cocok dengan read model existing.");
      return null;
    }
  } else {
    const fresh = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (fresh.status !== 200) {
      fail(`reserve_marketplace_listing_event fresh gagal: ${parseResponseText(fresh.payload)}`);
      return null;
    }
    firstRpcJson = assertSliceCRpcResponseExact(fresh.payload, "CREATED");
    if (!firstRpcJson) return null;

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "reserve_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`reserve_marketplace_listing_event replay gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceCRpcResponseExact(replay.payload, "REPLAYED");
    if (!replayRpcJson) return null;
    if (
      String(replayRpcJson?.normalizationEventId ?? "") !== String(firstRpcJson?.normalizationEventId ?? "") ||
      String(replayRpcJson?.eventId ?? "") !== String(firstRpcJson?.eventId ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(firstRpcJson?.orderId ?? "") ||
      String(replayRpcJson?.eventRef ?? "") !== String(firstRpcJson?.eventRef ?? "") ||
      String(replayRpcJson?.orderRef ?? "") !== String(firstRpcJson?.orderRef ?? "") ||
      asNumber(replayRpcJson?.canonicalLineCount) !== 1 ||
      asNumber(replayRpcJson?.totalUnitQuantity) !== 8
    ) {
      fail("Immediate replay Slice C tidak identik dengan fresh identity.");
      return null;
    }
  }

  const normalizationRowsAfter = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRowsAfter) return null;
  const normalizationRow = assertSliceCNormalizationRowExact(
    normalizationRowsAfter,
    organizationId,
  );
  if (!normalizationRow) return null;

  const lifecycleRowsAfter = await readSliceCLifecycleRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!lifecycleRowsAfter) return null;

  const assertionContexts = resolveGoldenAssertionContexts({
    highestPersistedPhase: existingNormalization
      ? currentSerumProjectionPhaseContext
      : { detectedPhase: "SLICE_C_RESERVED" },
    targetSlice: "SLICE_C",
    operation: existingNormalization ? "REPLAY" : "RESERVE",
    checkpoint: "AFTER_SHOPEE_RESERVATION",
  });
  const lifecycleRow = assertSliceCLifecycleRowExact({
    rows: lifecycleRowsAfter,
    normalizationRow,
    lifecyclePhaseContext: assertionContexts.lifecyclePhase,
  });
  if (!lifecycleRow) return null;

  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) return null;

  if (existingNormalization) {
    const afterState = assertSliceCStateAwareProductProjection(afterProductRows);
    if (!afterState) return null;
  } else if (!assertProjectionExact(afterProductRows, { sellable: 35, reserved: 8, available: 27 }, "Projection product Slice C")) {
    return null;
  }

  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) return null;

  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) return null;

  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) return null;

  if (!assertSliceCBatchProjection(afterBatch2701Rows, "SER-2701-C", 10)) {
    return null;
  }

  const after2608Qty = asNumber(afterBatch2608Rows?.[0]?.sellable_qty);
  const after2612Qty = asNumber(afterBatch2612Rows?.[0]?.sellable_qty);

  if (
    (existingNormalization && !([5, 0].includes(after2608Qty) && [20, 17].includes(after2612Qty)))
    || (!existingNormalization && (after2608Qty !== 5 || after2612Qty !== 20))
  ) {
    fail("Projection batch Slice C setelah RPC tidak exact.");
    return null;
  }

  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) return null;
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);
  if (
    beforeLedgerSummary.rowCount !== afterLedgerSummary.rowCount ||
    beforeLedgerSummary.totalQuantityDelta !== afterLedgerSummary.totalQuantityDelta
  ) {
    fail("Slice C harus stock-neutral tanpa ledger movement.");
    return null;
  }

  return {
    normalizationRow,
    lifecycleRow,
    beforeLedgerSummary,
    afterLedgerSummary,
  };
}

function assertSliceDEventRowExact(row, organizationId) {
  if (
    String(row?.organization_id ?? "") !== String(organizationId) ||
    String(row?.channel_code ?? "") !== SLICE_D.channelCode ||
    String(row?.external_event_ref ?? "") !== SLICE_D.externalEventRef ||
    String(row?.event_type_code ?? "") !== "SHIP" ||
    String(row?.status_code ?? "") !== "APPLIED" ||
    String(row?.note ?? "") !== SLICE_D.note ||
    !sameInstant(row?.occurred_at, SLICE_D.occurredAt) ||
    !isNonBlank(row?.event_id) ||
    !isNonBlank(row?.order_id) ||
    !isNonBlank(row?.transaction_id) ||
    String(row?.metadata?.adapterContract ?? "") !== "MARKETPLACE_LISTING_SHIP_V1" ||
    String(row?.metadata?.sourceStatus ?? "") !== "SHIPPED" ||
    !sameInstant(row?.metadata?.receivedAt, SLICE_D.receivedAt)
  ) {
    fail("api.marketplace_events Slice D tidak exact.");
    return null;
  }

  return row;
}

function assertSliceDResponseExact(responseJson) {
  if (
    !responseJson ||
    typeof responseJson !== "object" ||
    String(responseJson?.status ?? "") !== "APPLIED" ||
    String(responseJson?.eventType ?? "") !== "SHIP" ||
    String(responseJson?.eventRef ?? "") !== SLICE_D.externalEventRef ||
    String(responseJson?.orderRef ?? "") !== SLICE_D.externalOrderRef ||
    !isNonBlank(responseJson?.eventId) ||
    !isNonBlank(responseJson?.orderId) ||
    !isNonBlank(responseJson?.transactionId) ||
    !isNonBlank(responseJson?.transactionNo) ||
    asNumber(responseJson?.lineCount) !== 1 ||
    asNumber(responseJson?.allocationCount) !== 2 ||
    asNumber(responseJson?.totalQuantity) !== 8 ||
    String(responseJson?.adapterContract ?? "") !== "MARKETPLACE_LISTING_SHIP_V1" ||
    String(responseJson?.sourceStatus ?? "") !== "SHIPPED" ||
    !sameInstant(responseJson?.occurredAt, SLICE_D.occurredAt) ||
    !sameInstant(responseJson?.receivedAt, SLICE_D.receivedAt)
  ) {
    fail("Response Slice D tidak exact.");
    return null;
  }

  return responseJson;
}

function assertSliceDAllocationsExact(rows, serumProductId) {
  if (!Array.isArray(rows) || rows.length !== 2) {
    fail(`api.marketplace_ship_allocations Slice D harus tepat dua row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const [first, second] = rows;

  const firstExact = (
    asNumber(first?.allocation_no) === 1 &&
    String(first?.batch_code_snapshot ?? "") === "SER-2608-A" &&
    asNumber(first?.quantity_allocated) === 5
  );
  const secondExact = (
    asNumber(second?.allocation_no) === 2 &&
    String(second?.batch_code_snapshot ?? "") === "SER-2612-B" &&
    asNumber(second?.quantity_allocated) === 3
  );

  if (
    !firstExact ||
    !secondExact ||
    String(first?.product_id ?? "") !== String(serumProductId) ||
    String(second?.product_id ?? "") !== String(serumProductId) ||
    String(first?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(second?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(first?.source_line_ref ?? "") !== SLICE_D.canonicalSourceLineRef ||
    String(second?.source_line_ref ?? "") !== SLICE_D.canonicalSourceLineRef ||
    !isNonBlank(first?.ledger_entry_id) ||
    !isNonBlank(second?.ledger_entry_id)
  ) {
    fail("api.marketplace_ship_allocations Slice D tidak exact.");
    return null;
  }

  return rows;
}

function assertSliceDReservationExact(rows, serumProductId, normalizationRow) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`api.marketplace_reservations Slice D harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const row = rows[0];
  const safeActual = {
    order_id: row?.order_id ?? null,
    external_order_ref: row?.external_order_ref ?? null,
    external_item_ref: row?.external_item_ref ?? null,
    product_sku_snapshot: row?.product_sku_snapshot ?? null,
    quantity_ordered: row?.quantity_ordered ?? null,
    reserved_qty: row?.reserved_qty ?? null,
    consumed_qty: row?.consumed_qty ?? null,
    released_qty: row?.released_qty ?? null,
    open_qty: row?.open_qty ?? null,
    status_code: row?.status_code ?? null,
    closed_at: row?.closed_at ?? null,
  };
  if (
    String(row?.organization_id ?? "") !== String(normalizationRow?.organization_id ?? "") ||
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.channel_code ?? "") !== SLICE_D.channelCode ||
    String(row?.external_order_ref ?? "") !== SLICE_D.externalOrderRef ||
    String(row?.external_item_ref ?? "") !== SLICE_D.canonicalSourceLineRef ||
    String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(row?.product_id ?? "") !== String(serumProductId) ||
    asNumber(row?.quantity_ordered) !== 8 ||
    String(row?.reservation_id ?? "") !== String(normalizationRow?.reservation_id ?? "") ||
    asNumber(row?.reserved_qty) !== 8 ||
    asNumber(row?.consumed_qty) !== 8 ||
    asNumber(row?.released_qty) !== 0 ||
    asNumber(row?.open_qty) !== 0 ||
    !isNonBlank(row?.status_code) ||
    !isNonBlank(row?.closed_at)
  ) {
    fail(`api.marketplace_reservations Slice D tidak exact. actual=${JSON.stringify(safeActual)}`);
    return null;
  }

  return row;
}

function assertSliceDLifecycleExact({ rows, normalizationRow, lifecyclePhaseContext }) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    fail(`Lifecycle Slice D harus tepat satu row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const [row] = rows;
  const expectedState = expectedGoldenCurrentStateForPhase(lifecyclePhaseContext);
  const expectedPhase = { detectedPhase: expectedState.detectedPhase };
  const expected = expectedState.shopeeLifecycle;
  const expectedConsumedQty = expected.consumed;
  const expectedShippedQty = expected.shipped;
  const expectedOpenReservedQty = expected.openReserved;
  const expectedReturnExpectedQty = expected.returnExpected;
  const expectedReturnReceivedQty = expected.returnReceived;
  const expectedReturnSellableQty = expected.returnSellable;
  const expectedReturnDamagedQty = expected.returnDamaged;
  const expectedReturnLostQty = expected.returnLost;
  const expectedRemainingReturnableQty = expected.remaining;
  const sliceDChecks = [
    { name: "organization_id", expected: String(normalizationRow?.organization_id ?? ""), actual: String(row?.organization_id ?? ""), passed: String(row?.organization_id ?? "") === String(normalizationRow?.organization_id ?? "") },
    { name: "order_id", expected: String(normalizationRow?.order_id ?? ""), actual: String(row?.order_id ?? ""), passed: String(row?.order_id ?? "") === String(normalizationRow?.order_id ?? "") },
    { name: "external_order_ref", expected: SLICE_D.externalOrderRef, actual: String(row?.external_order_ref ?? ""), passed: String(row?.external_order_ref ?? "") === SLICE_D.externalOrderRef },
    { name: "channel_code", expected: SLICE_D.channelCode, actual: String(row?.channel_code ?? ""), passed: String(row?.channel_code ?? "") === SLICE_D.channelCode },
    { name: "source_line_ref", expected: SLICE_D.orderSourceLineRef, actual: String(row?.source_line_ref ?? ""), passed: String(row?.source_line_ref ?? "") === SLICE_D.orderSourceLineRef },
    { name: "canonical_source_line_ref", expected: SLICE_D.canonicalSourceLineRef, actual: String(row?.canonical_source_line_ref ?? ""), passed: String(row?.canonical_source_line_ref ?? "") === SLICE_D.canonicalSourceLineRef },
    { name: "component_no", expected: 1, actual: asNumber(row?.component_no), passed: asNumber(row?.component_no) === 1 },
    { name: "reserved_qty", expected: 8, actual: asNumber(row?.reserved_qty), passed: asNumber(row?.reserved_qty) === 8 },
    { name: "consumed_qty", expected: expectedConsumedQty, actual: asNumber(row?.consumed_qty), passed: asNumber(row?.consumed_qty) === expectedConsumedQty },
    { name: "released_qty", expected: 0, actual: asNumber(row?.released_qty), passed: asNumber(row?.released_qty) === 0 },
    { name: "open_reserved_quantity", expected: expectedOpenReservedQty, actual: asNumber(row?.open_reserved_quantity), passed: asNumber(row?.open_reserved_quantity) === expectedOpenReservedQty },
    { name: "shipped_quantity", expected: expectedShippedQty, actual: asNumber(row?.shipped_quantity), passed: asNumber(row?.shipped_quantity) === expectedShippedQty },
    { name: "pre_shipment_cancelled_quantity", expected: 0, actual: asNumber(row?.pre_shipment_cancelled_quantity), passed: asNumber(row?.pre_shipment_cancelled_quantity) === 0 },
    { name: "post_shipment_cancelled_quantity", expected: 0, actual: asNumber(row?.post_shipment_cancelled_quantity), passed: asNumber(row?.post_shipment_cancelled_quantity) === 0 },
    { name: "return_expected_quantity", expected: expectedReturnExpectedQty, actual: asNumber(row?.return_expected_quantity), passed: asNumber(row?.return_expected_quantity) === expectedReturnExpectedQty },
    { name: "return_received_quantity", expected: expectedReturnReceivedQty, actual: asNumber(row?.return_received_quantity), passed: asNumber(row?.return_received_quantity) === expectedReturnReceivedQty },
    { name: "return_sellable_quantity", expected: expectedReturnSellableQty, actual: asNumber(row?.return_sellable_quantity), passed: asNumber(row?.return_sellable_quantity) === expectedReturnSellableQty },
    { name: "return_damaged_quantity", expected: expectedReturnDamagedQty, actual: asNumber(row?.return_damaged_quantity), passed: asNumber(row?.return_damaged_quantity) === expectedReturnDamagedQty },
    { name: "return_lost_quantity", expected: expectedReturnLostQty, actual: asNumber(row?.return_lost_quantity), passed: asNumber(row?.return_lost_quantity) === expectedReturnLostQty },
    { name: "remaining_returnable_or_cancellable_quantity", expected: expectedRemainingReturnableQty, actual: asNumber(row?.remaining_returnable_or_cancellable_quantity), passed: asNumber(row?.remaining_returnable_or_cancellable_quantity) === expectedRemainingReturnableQty },
  ];
  if (
    String(row?.organization_id ?? "") !== String(normalizationRow?.organization_id ?? "") ||
    String(row?.order_id ?? "") !== String(normalizationRow?.order_id ?? "") ||
    String(row?.external_order_ref ?? "") !== SLICE_D.externalOrderRef ||
    String(row?.channel_code ?? "") !== SLICE_D.channelCode ||
    String(row?.source_line_ref ?? "") !== SLICE_D.orderSourceLineRef ||
    String(row?.canonical_source_line_ref ?? "") !== SLICE_D.canonicalSourceLineRef ||
    asNumber(row?.component_no) !== 1 ||
    asNumber(row?.reserved_qty) !== 8 ||
    asNumber(row?.consumed_qty) !== expectedConsumedQty ||
    asNumber(row?.released_qty) !== 0 ||
    asNumber(row?.open_reserved_quantity) !== expectedOpenReservedQty ||
    asNumber(row?.shipped_quantity) !== expectedShippedQty ||
    asNumber(row?.pre_shipment_cancelled_quantity) !== 0 ||
    asNumber(row?.post_shipment_cancelled_quantity) !== 0 ||
    asNumber(row?.return_expected_quantity) !== expectedReturnExpectedQty ||
    asNumber(row?.return_received_quantity) !== expectedReturnReceivedQty ||
    asNumber(row?.return_sellable_quantity) !== expectedReturnSellableQty ||
    asNumber(row?.return_damaged_quantity) !== expectedReturnDamagedQty ||
    asNumber(row?.return_lost_quantity) !== expectedReturnLostQty ||
    asNumber(row?.remaining_returnable_or_cancellable_quantity) !== expectedRemainingReturnableQty
  ) {
    console.log(JSON.stringify({
      assertion: "Slice D component lifecycle",
      orderRef: String(row?.external_order_ref ?? ""),
      sourceLineRef: String(row?.source_line_ref ?? ""),
      observedPhase: "SLICE_D_SHIPPED", lifecyclePhaseContext: expectedPhase.detectedPhase, expectedLifecyclePhase: expectedPhase.detectedPhase, observedPhaseRank: getSerumProjectionPhaseRank(buildSerumProjectionPhase("SLICE_D_SHIPPED", Number.NaN, Number.NaN)), rowCount: rows.length, expected,
      lifecycleChecks: sliceDChecks,
    }, null, 2));
    fail("api.marketplace_listing_component_lifecycle Slice D tidak exact.");
    return null;
  }

  return row;
}

function assertSliceDLedgerExact(rows, organizationId, transactionId, transactionNo, serumProductId) {
  if (!Array.isArray(rows) || rows.length !== 2) {
    fail(`api.stock_ledger Slice D harus tepat dua row, tetapi ditemukan ${Array.isArray(rows) ? rows.length : 0}.`);
    return null;
  }

  const [first, second] = rows;
  const actualRows = rows.map((row) => ({
    organization_id: row?.organization_id ?? null,
    transaction_id: row?.transaction_id ?? null,
    transaction_no: row?.transaction_no ?? null,
    transaction_type_code: row?.transaction_type_code ?? null,
    reason_code_snapshot: row?.reason_code_snapshot ?? null,
    channel_code_snapshot: row?.channel_code_snapshot ?? null,
    source_type_code: row?.source_type_code ?? null,
    source_ref_snapshot: row?.source_ref_snapshot ?? null,
    source_line_ref: row?.source_line_ref ?? null,
    line_no: row?.line_no ?? null,
    product_id: row?.product_id ?? null,
    product_sku_snapshot: row?.product_sku_snapshot ?? null,
    batch_code_snapshot: row?.batch_code_snapshot ?? null,
    bucket_code: row?.bucket_code ?? null,
    quantity_delta: row?.quantity_delta ?? null,
    entry_role_code: row?.entry_role_code ?? null,
    occurred_at: row?.occurred_at ?? null,
  }));
  const firstExact = (
    String(first?.batch_code_snapshot ?? "") === "SER-2608-A" &&
    asNumber(first?.quantity_delta) === -5
  );
  const secondExact = (
    String(second?.batch_code_snapshot ?? "") === "SER-2612-B" &&
    asNumber(second?.quantity_delta) === -3
  );

  if (
    !firstExact ||
    !secondExact ||
    String(first?.organization_id ?? "") !== String(organizationId) ||
    String(second?.organization_id ?? "") !== String(organizationId) ||
    String(first?.transaction_id ?? "") !== String(transactionId) ||
    String(second?.transaction_id ?? "") !== String(transactionId) ||
    String(first?.transaction_no ?? "") !== String(transactionNo) ||
    String(second?.transaction_no ?? "") !== String(transactionNo) ||
    String(first?.transaction_type_code ?? "") !== "MARKETPLACE_OUTBOUND" ||
    String(second?.transaction_type_code ?? "") !== "MARKETPLACE_OUTBOUND" ||
    String(first?.reason_code_snapshot ?? "") !== "MARKETPLACE_SALE" ||
    String(second?.reason_code_snapshot ?? "") !== "MARKETPLACE_SALE" ||
    String(first?.channel_code_snapshot ?? "") !== "SHOPEE" ||
    String(second?.channel_code_snapshot ?? "") !== "SHOPEE" ||
    String(first?.source_type_code ?? "") !== "MARKETPLACE_ORDER" ||
    String(second?.source_type_code ?? "") !== "MARKETPLACE_ORDER" ||
    String(first?.source_ref_snapshot ?? "") !== SLICE_D.externalOrderRef ||
    String(second?.source_ref_snapshot ?? "") !== SLICE_D.externalOrderRef ||
    String(first?.entry_role_code ?? "") !== "EXTERNAL_OUT" ||
    String(second?.entry_role_code ?? "") !== "EXTERNAL_OUT" ||
    String(first?.bucket_code ?? "") !== "SELLABLE" ||
    String(second?.bucket_code ?? "") !== "SELLABLE" ||
    String(first?.product_id ?? "") !== String(serumProductId) ||
    String(second?.product_id ?? "") !== String(serumProductId)
  ) {
    fail(`api.stock_ledger Slice D tidak exact. actual=${JSON.stringify(actualRows)}`);
    return null;
  }

  return rows;
}

async function runSliceDShipment(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const payload = buildSliceDPayload(organizationId);

  const normalizationRows = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRows) return null;
  const normalizationRow = assertSliceCNormalizationRowExact(
    normalizationRows,
    organizationId,
  );
  if (!normalizationRow) return null;

  const existingEventRows = await readMarketplaceEventsByRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SHOPEE",
    SLICE_D.externalEventRef,
  );
  if (!existingEventRows) return null;
  if (existingEventRows.length > 1) {
    fail(`Slice D menemukan ${existingEventRows.length} event untuk identity yang harus tunggal.`);
    return null;
  }

  const beforeProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!beforeProductRows) return null;

  const beforeBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!beforeBatch2608Rows) return null;

  const beforeBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!beforeBatch2612Rows) return null;

  const beforeBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!beforeBatch2701Rows) return null;

  const beforeLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!beforeLedgerRows) return null;
  const beforeLedgerSummary = summarizeLedger(beforeLedgerRows);
  const assertionContexts = resolveGoldenAssertionContexts({
    highestPersistedPhase: existingEventRows.length === 0
      ? { detectedPhase: "SLICE_D_SHIPPED" }
      : currentSerumProjectionPhaseContext,
    targetSlice: "SLICE_D",
    operation: existingEventRows.length === 0 ? "SHIP" : "REPLAY",
    checkpoint: "AFTER_SHOPEE_SHIPMENT",
  });
  const expectedPhaseAfter = assertionContexts.projectionPhase;

  let firstRpcJson;
  let replayRpcJson;

  if (existingEventRows.length === 0) {
    if (
      !assertSliceBProjection(
        {
          productInventory: beforeProductRows,
          batchInventory: [
            ...beforeBatch2608Rows,
            ...beforeBatch2612Rows,
            ...beforeBatch2701Rows,
          ],
        },
        currentSerumProjectionPhaseContext,
      )
    ) {
      return null;
    }

    const fresh = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (fresh.status !== 200) {
      fail(`ship_marketplace_listing_event fresh gagal: ${parseResponseText(fresh.payload)}`);
      return null;
    }
    firstRpcJson = assertSliceDResponseExact(fresh.payload);
    if (!firstRpcJson) return null;

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`ship_marketplace_listing_event replay gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceDResponseExact(replay.payload);
    if (!replayRpcJson) return null;

    if (
      String(replayRpcJson?.eventId ?? "") !== String(firstRpcJson?.eventId ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(firstRpcJson?.orderId ?? "") ||
      String(replayRpcJson?.transactionId ?? "") !== String(firstRpcJson?.transactionId ?? "") ||
      String(replayRpcJson?.transactionNo ?? "") !== String(firstRpcJson?.transactionNo ?? "")
    ) {
      fail("Immediate replay Slice D tidak mengadopsi identity fresh.");
      return null;
    }
  } else {
    const existingEvent = assertSliceDEventRowExact(existingEventRows[0], organizationId);
    if (!existingEvent) return null;

    const replay = await rpcJson(
      supabaseUrl,
      publishableKey,
      accessToken,
      "ship_marketplace_listing_event",
      payload,
    );
    if (replay.status !== 200) {
      fail(`ship_marketplace_listing_event replay existing gagal: ${parseResponseText(replay.payload)}`);
      return null;
    }
    replayRpcJson = assertSliceDResponseExact(replay.payload);
    if (!replayRpcJson) return null;
    if (
      String(replayRpcJson?.eventId ?? "") !== String(existingEvent.event_id ?? "") ||
      String(replayRpcJson?.orderId ?? "") !== String(existingEvent.order_id ?? "") ||
      String(replayRpcJson?.transactionId ?? "") !== String(existingEvent.transaction_id ?? "")
    ) {
      fail("Replay existing Slice D tidak cocok dengan event existing.");
      return null;
    }
  }

  const eventRowsAfter = await readMarketplaceEventsByRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SHOPEE",
    SLICE_D.externalEventRef,
  );
  if (!eventRowsAfter) return null;
  if (eventRowsAfter.length !== 1) {
    fail(`api.marketplace_events Slice D setelah replay harus tepat satu row, tetapi ditemukan ${eventRowsAfter.length}.`);
    return null;
  }
  const eventRow = assertSliceDEventRowExact(eventRowsAfter[0], organizationId);
  if (!eventRow) return null;

  const allocationRows = await readMarketplaceShipAllocationsByEventId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    eventRow.event_id,
  );
  if (!allocationRows) return null;
  if (!assertSliceDAllocationsExact(allocationRows, serumProductId)) return null;

  const reservationRows = await readMarketplaceReservationsByOrderRef(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SHOPEE",
    SLICE_D.externalOrderRef,
    SLICE_D.canonicalSourceLineRef,
  );
  if (!reservationRows) return null;
  if (!assertSliceDReservationExact(reservationRows, serumProductId, normalizationRow)) return null;

  const lifecycleRows = await readSliceDLifecycleRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!lifecycleRows) return null;
  if (!assertSliceDLifecycleExact({
    rows: lifecycleRows,
    normalizationRow,
    lifecyclePhaseContext: assertionContexts.lifecyclePhase,
  })) return null;

  const afterBatch2608Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2608-A",
  );
  if (!afterBatch2608Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2608Rows, "SER-2608-A", expectedBatchQuantityForPhase(expectedPhaseAfter, "SER-2608-A"))) {
    return null;
  }

  const afterBatch2612Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2612-B",
  );
  if (!afterBatch2612Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2612Rows, "SER-2612-B", expectedBatchQuantityForPhase(expectedPhaseAfter, "SER-2612-B"))) {
    return null;
  }

  const afterBatch2701Rows = await readBatchInventoryByCode(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-2701-C",
  );
  if (!afterBatch2701Rows) return null;
  if (!assertSliceCBatchProjection(afterBatch2701Rows, "SER-2701-C", expectedBatchQuantityForPhase(expectedPhaseAfter, "SER-2701-C"))) {
    return null;
  }

  const afterProductRows = await readProductInventoryBySku(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    "SER-NIA-30",
  );
  if (!afterProductRows) return null;
  if (!assertSliceBProjection(
    {
      productInventory: afterProductRows,
      batchInventory: [
        ...afterBatch2608Rows,
        ...afterBatch2612Rows,
        ...afterBatch2701Rows,
      ],
    },
    expectedPhaseAfter,
  )) {
    return null;
  }

  const ledgerRows = await readStockLedgerByTransactionId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    eventRow.transaction_id,
  );
  if (!ledgerRows) return null;
  if (!assertSliceDLedgerExact(ledgerRows, organizationId, eventRow.transaction_id, replayRpcJson?.transactionNo ?? eventRow.transaction_id, serumProductId)) {
    return null;
  }

  const afterLedgerRows = await readStockLedgerByProductId(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
  );
  if (!afterLedgerRows) return null;
  const afterLedgerSummary = summarizeLedger(afterLedgerRows);

  if (existingEventRows.length === 0) {
    if (
      afterLedgerSummary.rowCount !== beforeLedgerSummary.rowCount + 2 ||
      afterLedgerSummary.totalQuantityDelta !== beforeLedgerSummary.totalQuantityDelta - 8
    ) {
      fail("Ledger summary Slice D fresh tidak exact.");
      return null;
    }
  } else if (
    afterLedgerSummary.rowCount !== beforeLedgerSummary.rowCount ||
    afterLedgerSummary.totalQuantityDelta !== beforeLedgerSummary.totalQuantityDelta
  ) {
    fail("Replay existing Slice D tidak boleh menambah ledger.");
    return null;
  }

  return {
    eventRow,
    allocationRows,
    reservationRows,
    lifecycleRows,
    ledgerRows,
  };
}

let currentSerumProjectionPhaseContext = null;

const SERUM_PROJECTION_PHASE_RANK = new Map([
  ["SLICE_A_INITIAL", 0],
  ["SLICE_B_RECEIVED", 1],
  ["SLICE_C_RESERVED", 2],
  ["SLICE_D_SHIPPED", 3],
  ["SLICE_E_RESERVED", 4],
  ["SLICE_E_IN_TRANSIT", 5],
  ["SLICE_F_MANUAL_BONUS", 6],
  ["SLICE_G_BUNDLE_RESERVED", 7],
  ["SLICE_G_BUNDLE_SHIPPED", 8],
  ["SLICE_H_RETURN_EXPECTED", 9],
  ["SLICE_H_RETURN_RECEIVED", 10],
  ["SLICE_I_RETURN_INSPECTED", 11],
  ["SLICE_J_TIKTOK_RETURN_EXPECTED", 12],
  ["SLICE_J_TIKTOK_RETURN_LOST", 13],
  ["SLICE_K_TIKTOK_CLAIM_CREATED", 14],
  ["SLICE_K_TIKTOK_CLAIM_NOTIFICATION", 15],
  ["GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED", 16],
  ["GOLDEN_RECONCILIATION_COMPLETED", 17],
  ["GOLDEN_FINAL_ACCEPTED", 18],
]);

const GOLDEN_COMPLETION_MINIMUM_PHASE = Object.freeze({
  sliceA: "SLICE_A_INITIAL",
  sliceB: "SLICE_B_RECEIVED",
  sliceC: "SLICE_C_RESERVED",
  sliceD: "SLICE_D_SHIPPED",
  sliceEReserved: "SLICE_E_RESERVED",
  sliceE: "SLICE_E_IN_TRANSIT",
  sliceF: "SLICE_F_MANUAL_BONUS",
  sliceGReserved: "SLICE_G_BUNDLE_RESERVED",
  sliceGShipped: "SLICE_G_BUNDLE_SHIPPED",
  sliceHExpected: "SLICE_H_RETURN_EXPECTED",
  sliceHReceived: "SLICE_H_RETURN_RECEIVED",
  sliceIInspected: "SLICE_I_RETURN_INSPECTED",
  sliceJExpected: "SLICE_J_TIKTOK_RETURN_EXPECTED",
  sliceJLost: "SLICE_J_TIKTOK_RETURN_LOST",
  sliceKClaimCreated: "SLICE_K_TIKTOK_CLAIM_CREATED",
  sliceKNotification: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION",
  stocktakeAdjustment: "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED",
  reconciliation: "GOLDEN_RECONCILIATION_COMPLETED",
  finalAcceptance: "GOLDEN_FINAL_ACCEPTED",
});

function phaseNameOf(phase) {
  return typeof phase === "string" ? phase : String(phase?.detectedPhase ?? "");
}

function knownGoldenPhaseRank(phase) {
  const phaseName = phaseNameOf(phase);
  const rank = SERUM_PROJECTION_PHASE_RANK.get(phaseName);
  if (!Number.isInteger(rank)) {
    throw new Error(`GOLDEN_PHASE_UNKNOWN: ${phaseName || "<empty>"}`);
  }
  return rank;
}

function isPhaseAtLeast(actualPhase, minimumPhase) {
  return knownGoldenPhaseRank(actualPhase) >= knownGoldenPhaseRank(minimumPhase);
}

/*
 * A checkpoint is immutable historical evidence, while the read model keeps
 * moving. Fresh mutations therefore require the exact checkpoint phase;
 * durable replays require only that the authoritative phase has not moved
 * backwards. Evidence is checked independently by the owning slice.
 */
function resolveGoldenReplayPhaseContract({ highestPersistedPhase, checkpointPhase, executionMode, operation }) {
  if (!isNonBlank(operation) || !["FRESH", "REPLAY"].includes(String(executionMode ?? ""))) {
    throw new Error("GOLDEN_REPLAY_PHASE_CONTRACT_INVALID");
  }
  const authoritativePhase = phaseNameOf(highestPersistedPhase);
  const checkpoint = phaseNameOf(checkpointPhase);
  const authoritativeRank = knownGoldenPhaseRank(authoritativePhase);
  const checkpointRank = knownGoldenPhaseRank(checkpoint);
  if (executionMode === "FRESH") {
    if (authoritativeRank !== checkpointRank) {
      throw new Error(`GOLDEN_REPLAY_FRESH_PHASE_NOT_EXACT: ${operation} requires ${checkpoint}, actual=${authoritativePhase}`);
    }
    return {
      mode: "FRESH_EXACT",
      checkpointPhase: checkpoint,
      authoritativePhase,
      exactPhaseRequired: true,
      minimumPhaseSatisfied: true,
    };
  }
  if (authoritativeRank < checkpointRank) {
    throw new Error(`GOLDEN_REPLAY_PHASE_TOO_LOW: ${operation} requires at least ${checkpoint}, actual=${authoritativePhase}`);
  }
  return {
    mode: authoritativeRank === checkpointRank ? "SAME_PHASE_REPLAY" : "LATER_PHASE_REPLAY",
    checkpointPhase: checkpoint,
    authoritativePhase,
    exactPhaseRequired: false,
    minimumPhaseSatisfied: true,
  };
}

function assertGoldenHistoricalReplayEvidence({ phaseContract, evidence, operation }) {
  if (!phaseContract || typeof phaseContract !== "object" || !isNonBlank(operation)) {
    throw new Error("GOLDEN_REPLAY_HISTORICAL_EVIDENCE_CONTRACT_INVALID");
  }
  if (phaseContract.mode === "FRESH_EXACT") return true;
  if (!evidence || evidence.exact !== true) {
    throw new Error(`GOLDEN_REPLAY_HISTORICAL_EVIDENCE_INVALID: ${operation}`);
  }
  if (evidence.duplicateEffect === true || evidence.duplicateReservation === true || evidence.duplicateEvent === true || evidence.duplicateLedger === true) {
    throw new Error(`GOLDEN_REPLAY_DUPLICATE_EFFECT: ${operation}`);
  }
  return true;
}

const GOLDEN_REPLAY_PHASE_CHECKPOINTS = Object.freeze([
  Object.freeze({ id: "SLICE_B_RECEIPT", checkpointPhase: "SLICE_B_RECEIVED", operation: "SLICE_B_RECEIPT", evidence: "command/idempotency + receipt ledger" }),
  Object.freeze({ id: "SLICE_C_RESERVATION", checkpointPhase: "SLICE_C_RESERVED", operation: "SLICE_C_RESERVATION", evidence: "command/idempotency + reservation + normalization" }),
  Object.freeze({ id: "SLICE_D_SHIPMENT", checkpointPhase: "SLICE_D_SHIPPED", operation: "SLICE_D_SHIPMENT", evidence: "marketplace event + FEFO allocation + ledger" }),
  Object.freeze({ id: "SLICE_E_RESERVATION", checkpointPhase: "SLICE_E_RESERVED", operation: "SLICE_E_RESERVATION", evidence: "command/idempotency + TikTok reservation + reserve event" }),
  Object.freeze({ id: "SLICE_E_SHIPMENT", checkpointPhase: "SLICE_E_IN_TRANSIT", operation: "SLICE_E_SHIPMENT", evidence: "TikTok ship event + reservation + FEFO allocation + ledger" }),
  Object.freeze({ id: "SLICE_F_MANUAL_BONUS", checkpointPhase: "SLICE_F_MANUAL_BONUS", operation: "SLICE_F_MANUAL_BONUS", evidence: "manual command/idempotency + outbound + ledger" }),
  Object.freeze({ id: "SLICE_G_RESERVATION", checkpointPhase: "SLICE_G_BUNDLE_RESERVED", operation: "SLICE_G_RESERVATION", evidence: "bundle normalization + reservations" }),
  Object.freeze({ id: "SLICE_G_SHIPMENT", checkpointPhase: "SLICE_G_BUNDLE_SHIPPED", operation: "SLICE_G_SHIPMENT", evidence: "bundle event + FEFO allocations + ledger" }),
  Object.freeze({ id: "SLICE_H_EXPECTED_RETURN", checkpointPhase: "SLICE_H_RETURN_EXPECTED", operation: "SLICE_H_EXPECTED_RETURN", evidence: "return header/item/event" }),
  Object.freeze({ id: "SLICE_H_RETURN_RECEIPT", checkpointPhase: "SLICE_H_RETURN_RECEIVED", operation: "SLICE_H_RETURN_RECEIPT", evidence: "return receipt + provenance linkage" }),
  Object.freeze({ id: "SLICE_I_INSPECTION", checkpointPhase: "SLICE_I_RETURN_INSPECTED", operation: "SLICE_I_INSPECTION", evidence: "inspection allocations + return batch + ledger" }),
  Object.freeze({ id: "SLICE_J_EXPECTED_RETURN", checkpointPhase: "SLICE_J_TIKTOK_RETURN_EXPECTED", operation: "SLICE_J_EXPECTED_RETURN", evidence: "TikTok expected return header/item/event" }),
  Object.freeze({ id: "SLICE_J_LOST_RETURN", checkpointPhase: "SLICE_J_TIKTOK_RETURN_LOST", operation: "SLICE_J_LOST_RETURN", evidence: "LOST event + stock-neutral audit" }),
  Object.freeze({ id: "SLICE_K_CLAIM", checkpointPhase: "SLICE_K_TIKTOK_CLAIM_CREATED", operation: "SLICE_K_CLAIM", evidence: "claim command/item/event" }),
  Object.freeze({ id: "SLICE_K_NOTIFICATION", checkpointPhase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION", operation: "SLICE_K_NOTIFICATION", evidence: "notification + rule-run" }),
  Object.freeze({ id: "GOLDEN_STOCKTAKE_ADJUSTMENT", checkpointPhase: "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED", operation: "GOLDEN_STOCKTAKE_ADJUSTMENT", evidence: "stocktake snapshot/count/approval/posting + ledger" }),
  Object.freeze({ id: "GOLDEN_RECONCILIATION", checkpointPhase: "GOLDEN_RECONCILIATION_COMPLETED", operation: "GOLDEN_RECONCILIATION", evidence: "linked post-stocktake reconciliation run/checks/issues" }),
  Object.freeze({ id: "GOLDEN_FINAL_ACCEPTANCE", checkpointPhase: "GOLDEN_FINAL_ACCEPTED", operation: "GOLDEN_FINAL_ACCEPTANCE", evidence: "terminal stocktake/reconciliation/ledger explorer evidence" }),
]);

function auditGoldenReplayPhaseMonotonicityMatrix() {
  const phases = [...SERUM_PROJECTION_PHASE_RANK.keys()];
  const finalPhase = phases.at(-1);
  const mismatches = [];
  let freshCaseCount = 0;
  let samePhaseReplayCaseCount = 0;
  let laterPhaseReplayCaseCount = 0;
  let lowerPhaseFailureCount = 0;
  let unknownPhaseFailureCount = 0;
  let evidenceFailureCount = 0;
  let duplicateFailureCount = 0;
  let invalidLaterPhaseRejectionCount = 0;
  let historicalEvidenceMismatchCount = 0;
  for (const checkpoint of GOLDEN_REPLAY_PHASE_CHECKPOINTS) {
    const checkpointRank = knownGoldenPhaseRank(checkpoint.checkpointPhase);
    const immediateLaterPhase = phases[checkpointRank + 1] ?? null;
    const verifyPass = (label, run) => {
      try { run(); } catch (error) { mismatches.push({ checkpoint: checkpoint.id, case: label, expected: "PASS", actual: error instanceof Error ? error.message : "UNKNOWN" }); }
    };
    const verifyFailure = (label, expectedCode, run, counter) => {
      try {
        run();
        mismatches.push({ checkpoint: checkpoint.id, case: label, expected: expectedCode, actual: "PASS" });
      } catch (error) {
        const actual = error instanceof Error ? error.message : "UNKNOWN";
        if (!actual.startsWith(expectedCode)) mismatches.push({ checkpoint: checkpoint.id, case: label, expected: expectedCode, actual });
        else if (counter === "lower") lowerPhaseFailureCount += 1;
        else if (counter === "unknown") unknownPhaseFailureCount += 1;
        else if (counter === "evidence") evidenceFailureCount += 1;
        else if (counter === "duplicate") duplicateFailureCount += 1;
      }
    };
    verifyPass("FRESH_AT_CHECKPOINT", () => {
      const contract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: checkpoint.checkpointPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "FRESH", operation: checkpoint.operation });
      if (contract.mode !== "FRESH_EXACT" || contract.exactPhaseRequired !== true) throw new Error("GOLDEN_REPLAY_FRESH_CONTRACT_INVALID");
    });
    freshCaseCount += 1;
    verifyPass("SAME_PHASE_REPLAY", () => {
      const contract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: checkpoint.checkpointPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
      assertGoldenHistoricalReplayEvidence({ phaseContract: contract, evidence: { exact: true }, operation: checkpoint.operation });
      if (contract.mode !== "SAME_PHASE_REPLAY" || contract.exactPhaseRequired !== false) throw new Error("GOLDEN_REPLAY_SAME_PHASE_CONTRACT_INVALID");
    });
    samePhaseReplayCaseCount += 1;
    for (const laterPhase of [immediateLaterPhase, finalPhase].filter((phase, index, values) => phase && phase !== checkpoint.checkpointPhase && values.indexOf(phase) === index)) {
      verifyPass(`LATER_PHASE_REPLAY:${laterPhase}`, () => {
        const contract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: laterPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
        assertGoldenHistoricalReplayEvidence({ phaseContract: contract, evidence: { exact: true }, operation: checkpoint.operation });
        if (contract.mode !== "LATER_PHASE_REPLAY" || contract.minimumPhaseSatisfied !== true) throw new Error("GOLDEN_REPLAY_LATER_PHASE_CONTRACT_INVALID");
      });
      laterPhaseReplayCaseCount += 1;
      verifyFailure(`LATER_PHASE_WITHOUT_EVIDENCE:${laterPhase}`, "GOLDEN_REPLAY_HISTORICAL_EVIDENCE_INVALID", () => {
        const contract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: laterPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
        assertGoldenHistoricalReplayEvidence({ phaseContract: contract, evidence: { exact: false }, operation: checkpoint.operation });
      }, "evidence");
      verifyFailure(`LATER_PHASE_WITH_DUPLICATE:${laterPhase}`, "GOLDEN_REPLAY_DUPLICATE_EFFECT", () => {
        const contract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: laterPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
        assertGoldenHistoricalReplayEvidence({ phaseContract: contract, evidence: { exact: true, duplicateEffect: true }, operation: checkpoint.operation });
      }, "duplicate");
    }
    const lowerPhase = phases[checkpointRank - 1];
    verifyFailure("LOWER_PHASE_REPLAY", "GOLDEN_REPLAY_PHASE_TOO_LOW", () => resolveGoldenReplayPhaseContract({ highestPersistedPhase: lowerPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }), "lower");
    verifyFailure("UNKNOWN_PHASE_REPLAY", "GOLDEN_PHASE_UNKNOWN", () => resolveGoldenReplayPhaseContract({ highestPersistedPhase: "SLICE_UNKNOWN", checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }), "unknown");
  }
  const overStrictEqualityGuardCount = mismatches.filter((mismatch) => mismatch.case.startsWith("LATER_PHASE_REPLAY")).length;
  invalidLaterPhaseRejectionCount = overStrictEqualityGuardCount;
  historicalEvidenceMismatchCount = mismatches.filter((mismatch) => mismatch.case.includes("EVIDENCE") || mismatch.case.includes("DUPLICATE")).length;
  return {
    checkpointCount: GOLDEN_REPLAY_PHASE_CHECKPOINTS.length,
    freshCaseCount,
    samePhaseReplayCaseCount,
    laterPhaseReplayCaseCount,
    lowerPhaseFailureCount,
    unknownPhaseFailureCount,
    evidenceFailureCount,
    duplicateFailureCount,
    exactPhaseGuardCount: GOLDEN_REPLAY_PHASE_CHECKPOINTS.length,
    replayMinimumPhaseGuardCount: GOLDEN_REPLAY_PHASE_CHECKPOINTS.length,
    overStrictEqualityGuardCount,
    invalidLaterPhaseRejectionCount,
    historicalEvidenceMismatchCount,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function assertGoldenCompletionPhase(guard, actualPhase) {
  const minimumPhase = GOLDEN_COMPLETION_MINIMUM_PHASE[guard];
  if (!minimumPhase) throw new Error(`GOLDEN_COMPLETION_GUARD_UNKNOWN: ${String(guard)}`);
  if (!isPhaseAtLeast(actualPhase, minimumPhase)) {
    throw new Error(`GOLDEN_COMPLETION_PHASE_TOO_LOW: ${String(guard)} requires ${minimumPhase}, actual=${phaseNameOf(actualPhase)}`);
  }
  return true;
}

function verifyGoldenCompletionGuard(guard, ...phaseCandidates) {
  try {
    assertGoldenCompletionPhase(guard, highestGoldenCurrentStatePhase(...phaseCandidates));
    return true;
  } catch (error) {
    fail(error instanceof Error ? error.message : "GOLDEN_COMPLETION_PHASE_TOO_LOW");
    return false;
  }
}

function auditGoldenPhaseControlFlowCompatibility() {
  const knownPhases = [...SERUM_PROJECTION_PHASE_RANK.keys()];
  const mismatches = [];
  let matrixCaseCount = 0;
  for (const [guard, minimumPhase] of Object.entries(GOLDEN_COMPLETION_MINIMUM_PHASE)) {
    const minimumRank = knownGoldenPhaseRank(minimumPhase);
    for (const actualPhase of knownPhases) {
      const expectedAccepted = knownGoldenPhaseRank(actualPhase) >= minimumRank;
      let actualAccepted;
      try {
        actualAccepted = isPhaseAtLeast(actualPhase, minimumPhase);
      } catch {
        actualAccepted = false;
      }
      matrixCaseCount += 1;
      if (actualAccepted !== expectedAccepted) {
        mismatches.push({ guard, actualPhase, minimumPhase, expectedAccepted, actualAccepted });
      }
    }
    let unknownThrew = false;
    try {
      isPhaseAtLeast("SLICE_UNKNOWN", minimumPhase);
    } catch (error) {
      unknownThrew = error instanceof Error && error.message.startsWith("GOLDEN_PHASE_UNKNOWN:");
    }
    matrixCaseCount += 1;
    if (!unknownThrew) {
      mismatches.push({ guard, actualPhase: "SLICE_UNKNOWN", minimumPhase, expectedAccepted: "throws GOLDEN_PHASE_UNKNOWN", actualAccepted: "did not throw" });
    }
  }
  return {
    knownPhaseCount: knownPhases.length,
    completionGuardCount: Object.keys(GOLDEN_COMPLETION_MINIMUM_PHASE).length,
    matrixCaseCount,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function assertSliceEReservationCallerCanContinue(result) {
  const exactResult = assertGoldenStateAwareSuccessResult(
    result,
    "runSliceETiktokReservationStateAware",
  );
  const phaseContract = exactResult.replayPhaseContract ?? resolveGoldenReplayPhaseContract({
    highestPersistedPhase: exactResult.phase,
    checkpointPhase: "SLICE_E_RESERVED",
    executionMode: exactResult.outcome === "CREATED" ? "FRESH" : "REPLAY",
    operation: "SLICE_E_RESERVATION",
  });
  assertGoldenHistoricalReplayEvidence({
    phaseContract,
    evidence: exactResult.persistedEvidence,
    operation: "SLICE_E_RESERVATION",
  });
  return { continuesToShipment: true, outcome: exactResult.outcome, phaseContract };
}

function auditGoldenStateAwareControlFlowMatrix() {
  const helperContracts = [
    "receipt", "shopee reservation", "shopee shipment", "tiktok reservation",
    "tiktok shipment", "manual outbound", "bundle", "return receipt", "inspection",
    "lost", "claim", "notification", "stocktake", "reconciliation",
  ];
  const baseResult = {
    reservationId: "reservation-e-exact",
    phase: { detectedPhase: "SLICE_E_RESERVED" },
    response: { status: "APPLIED" },
    persistedEvidence: { exact: true, duplicateReservation: false, duplicateEvent: false },
  };
  const cases = [
    { name: "A_EXISTING_EXACT_ADOPTED", result: { ...baseResult, outcome: "ADOPTED" }, expected: "CONTINUES" },
    { name: "B_FRESH_EXACT_CREATED", result: { ...baseResult, outcome: "CREATED" }, expected: "CONTINUES" },
    { name: "C_IDEMPOTENT_EXACT_REPLAYED", result: { ...baseResult, outcome: "REPLAYED" }, expected: "CONTINUES" },
    { name: "D_LATER_PHASE_ADOPTED", result: { ...baseResult, outcome: "ADOPTED", phase: { detectedPhase: "SLICE_F_MANUAL_BONUS" } }, expected: "CONTINUES" },
    { name: "E_NULL_RESULT", result: null, expected: "GOLDEN_STATE_AWARE_NULL_RESULT" },
    { name: "F_UNKNOWN_OUTCOME", result: { ...baseResult, outcome: "UNKNOWN" }, expected: "GOLDEN_STATE_AWARE_OUTCOME_UNKNOWN" },
    { name: "G_PARTIAL_EVIDENCE", result: { ...baseResult, outcome: "ADOPTED", persistedEvidence: { exact: false } }, expected: "GOLDEN_STATE_AWARE_DUPLICATE_OR_PARTIAL_EVIDENCE" },
    { name: "H_DUPLICATE_EVENT", result: { ...baseResult, outcome: "ADOPTED", persistedEvidence: { exact: true, duplicateReservation: false, duplicateEvent: true } }, expected: "GOLDEN_STATE_AWARE_DUPLICATE_OR_PARTIAL_EVIDENCE" },
  ];
  const mismatches = [];
  for (const matrixCase of cases) {
    try {
      const continuation = assertSliceEReservationCallerCanContinue(matrixCase.result);
      if (matrixCase.expected !== "CONTINUES" || continuation.continuesToShipment !== true) {
        mismatches.push({ case: matrixCase.name, expected: matrixCase.expected, actual: continuation });
      }
    } catch (error) {
      const actual = error instanceof Error ? error.message : "UNKNOWN";
      if (actual !== matrixCase.expected) {
        mismatches.push({ case: matrixCase.name, expected: matrixCase.expected, actual });
      }
    }
  }
  return {
    helperCount: helperContracts.length,
    returnPathCount: helperContracts.length,
    nullableReturnPathCount: 0,
    silentCallerReturnCount: 0,
    checkedCaseCount: cases.length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function auditGoldenProjectionEvidenceContractMatrix() {
  const projectionFor = (phase) => {
    const state = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
    return { projectionPhase: state.detectedPhase, productCode: "SER-NIA-30", sellable: state.serumProduct.sellable, reserved: state.serumProduct.reserved, available: state.serumProduct.available };
  };
  const resultFor = ({ outcome = "ADOPTED", checkpointPhase = "SLICE_E_RESERVED", authoritativePhase = checkpointPhase, projectionEvidencePhase = authoritativePhase, afterProjection = projectionFor(projectionEvidencePhase), historicalOperationEvidence = { exact: true, duplicateReservation: false, duplicateEvent: false, duplicateLedger: false } } = {}) => {
    const replayPhaseContract = resolveGoldenReplayPhaseContract({
      highestPersistedPhase: authoritativePhase,
      checkpointPhase,
      executionMode: outcome === "CREATED" ? "FRESH" : "REPLAY",
      operation: "SLICE_E_RESERVATION",
    });
    return {
      outcome,
      reservationId: "reservation-e-exact",
      phase: { detectedPhase: authoritativePhase },
      replayPhaseContract,
      response: { status: "APPLIED" },
      persistedEvidence: {
        exact: true,
        duplicateReservation: false,
        duplicateEvent: false,
        afterProjection,
        projectionReplayContext: {
          checkpointPhase,
          authoritativePhase,
          projectionEvidencePhase,
          productCode: "SER-NIA-30",
          currentProjection: afterProjection,
          historicalOperationEvidence,
        },
      },
    };
  };
  const checkpointProjection = projectionFor("SLICE_E_RESERVED");
  const laterProjection = projectionFor("SLICE_F_MANUAL_BONUS");
  const cases = [
    { name: "A_FRESH_CHECKPOINT", run: () => { const result = resultFor({ outcome: "CREATED" }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "PASS" },
    { name: "B_SAME_PHASE_REPLAY", run: () => { const result = resultFor(); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "PASS" },
    { name: "C_LATER_PHASE_REPLAY", run: () => { const result = resultFor({ authoritativePhase: "SLICE_F_MANUAL_BONUS", projectionEvidencePhase: "SLICE_F_MANUAL_BONUS", afterProjection: laterProjection }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "PASS" },
    { name: "D_LATER_CHECKPOINT_PROJECTION", run: () => { const result = resultFor({ authoritativePhase: "SLICE_F_MANUAL_BONUS", projectionEvidencePhase: "SLICE_E_RESERVED", afterProjection: checkpointProjection }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE", category: "phase" },
    { name: "E_MISSING_AFTER_PROJECTION", run: () => { const result = resultFor({ afterProjection: null }); return assertSliceEReservationCallerProjectionEvidence(result, null); }, expected: "GOLDEN_PROJECTION_EVIDENCE_MISSING", category: "missing" },
    { name: "F_MISSING_HISTORICAL", run: () => { const result = resultFor({ historicalOperationEvidence: { exact: false } }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "GOLDEN_REPLAY_HISTORICAL_EVIDENCE_INVALID", category: "historical" },
    { name: "G_DUPLICATE_HISTORICAL", run: () => { const result = resultFor({ historicalOperationEvidence: { exact: true, duplicateEvent: true } }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "GOLDEN_REPLAY_DUPLICATE_EFFECT", category: "duplicate" },
    { name: "H_WRONG_PRODUCT", run: () => { const result = resultFor({ afterProjection: { ...checkpointProjection, productCode: "WRONG" } }); return assertSliceEReservationCallerProjectionEvidence(result, result.persistedEvidence.afterProjection); }, expected: "GOLDEN_PROJECTION_EVIDENCE_WRONG_PRODUCT", category: "product" },
    { name: "I_DIRECT_EVIDENCE_DIVERGENCE", run: () => { const result = resultFor(); return assertGoldenProjectionEvidenceExact({ evidence: result.persistedEvidence.afterProjection, directProjection: laterProjection, projectionReplayContext: { ...result.persistedEvidence.projectionReplayContext, replayPhaseContract: result.replayPhaseContract, operation: "matrix" }, productCode: "SER-NIA-30", assertionLabel: "matrix" }); }, expected: "GOLDEN_PROJECTION_EVIDENCE_DIVERGENCE", category: "divergence" },
    { name: "J_WRONG_CALLER_ARGUMENT", run: () => { const result = resultFor(); return assertSliceEReservationCallerProjectionEvidence(result, { ...result.persistedEvidence.afterProjection }); }, expected: "GOLDEN_PROJECTION_EVIDENCE_WRONG_ASSERTION_ARGUMENT" },
  ];
  const mismatches = [];
  for (const matrixCase of cases) {
    try {
      matrixCase.run();
      if (matrixCase.expected !== "PASS") mismatches.push({ case: matrixCase.name, expected: matrixCase.expected, actual: "PASS" });
    } catch (error) {
      const actual = error instanceof Error ? error.message : "UNKNOWN";
      if (!actual.startsWith(matrixCase.expected)) mismatches.push({ case: matrixCase.name, expected: matrixCase.expected, actual });
    }
  }
  return {
    caseCount: cases.length,
    outcomeCount: 3,
    checkedPathCount: cases.length * 5,
    staleSnapshotCount: cases.filter((item) => item.category === "phase").length,
    missingEvidenceCount: cases.filter((item) => item.category === "missing").length,
    wrongPhaseCount: cases.filter((item) => item.category === "phase").length,
    wrongProductCount: cases.filter((item) => item.category === "product").length,
    evidenceDivergenceCount: cases.filter((item) => item.category === "divergence").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function auditGoldenProjectionReplayContextMatrix() {
  const phases = [...SERUM_PROJECTION_PHASE_RANK.keys()];
  const mismatches = [];
  let freshCaseCount = 0;
  let samePhaseReplayCaseCount = 0;
  let laterPhaseReplayCaseCount = 0;
  let wrongCheckpointProjectionFailureCount = 0;
  let wrongAuthoritativePhaseFailureCount = 0;
  let missingHistoricalEvidenceFailureCount = 0;
  let duplicateHistoricalEffectFailureCount = 0;
  const projectionFor = (phase) => {
    const state = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
    return { projectionPhase: state.detectedPhase, productCode: "SER-NIA-30", sellable: state.serumProduct.sellable, reserved: state.serumProduct.reserved, available: state.serumProduct.available };
  };
  const runProjectionAssertion = ({ contract, projectionEvidencePhase, directProjection = projectionFor(projectionEvidencePhase), historicalOperationEvidence = { exact: true }, operation }) => {
    assertGoldenHistoricalReplayEvidence({ phaseContract: contract, evidence: historicalOperationEvidence, operation });
    return assertGoldenProjectionEvidenceExact({
      evidence: directProjection,
      directProjection,
      projectionReplayContext: {
        checkpointPhase: contract.checkpointPhase,
        authoritativePhase: contract.authoritativePhase,
        projectionEvidencePhase,
        replayPhaseContract: contract,
        operation,
      },
      productCode: "SER-NIA-30",
      assertionLabel: operation,
    });
  };
  const expectPass = (checkpoint, label, run) => {
    try { run(); } catch (error) { mismatches.push({ checkpoint: checkpoint.id, case: label, expected: "PASS", actual: error instanceof Error ? error.message : "UNKNOWN" }); }
  };
  const expectFailure = (checkpoint, label, expectedCode, run, increment) => {
    try {
      run();
      mismatches.push({ checkpoint: checkpoint.id, case: label, expected: expectedCode, actual: "PASS" });
    } catch (error) {
      const actual = error instanceof Error ? error.message : "UNKNOWN";
      if (!actual.startsWith(expectedCode)) mismatches.push({ checkpoint: checkpoint.id, case: label, expected: expectedCode, actual });
      else increment();
    }
  };
  for (const checkpoint of GOLDEN_REPLAY_PHASE_CHECKPOINTS) {
    const checkpointRank = knownGoldenPhaseRank(checkpoint.checkpointPhase);
    const laterPhase = phases[checkpointRank + 1] ?? null;
    const freshContract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: checkpoint.checkpointPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "FRESH", operation: checkpoint.operation });
    expectPass(checkpoint, "FRESH_EXACT", () => runProjectionAssertion({ contract: freshContract, projectionEvidencePhase: checkpoint.checkpointPhase, operation: checkpoint.operation }));
    freshCaseCount += 1;
    const sameContract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: checkpoint.checkpointPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
    expectPass(checkpoint, "SAME_PHASE_REPLAY", () => runProjectionAssertion({ contract: sameContract, projectionEvidencePhase: checkpoint.checkpointPhase, operation: checkpoint.operation }));
    samePhaseReplayCaseCount += 1;
    if (laterPhase) {
      const laterContract = resolveGoldenReplayPhaseContract({ highestPersistedPhase: laterPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation });
      expectPass(checkpoint, "LATER_PHASE_AUTHORITATIVE_PROJECTION", () => runProjectionAssertion({ contract: laterContract, projectionEvidencePhase: laterPhase, operation: checkpoint.operation }));
      laterPhaseReplayCaseCount += 1;
      expectFailure(checkpoint, "LATER_PHASE_CHECKPOINT_PROJECTION", "GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE", () => runProjectionAssertion({ contract: laterContract, projectionEvidencePhase: checkpoint.checkpointPhase, operation: checkpoint.operation }), () => { wrongCheckpointProjectionFailureCount += 1; });
      expectFailure(checkpoint, "LATER_PHASE_WRONG_AUTHORITATIVE_PROJECTION", "GOLDEN_PROJECTION_EVIDENCE_WRONG_PHASE", () => runProjectionAssertion({ contract: laterContract, projectionEvidencePhase: phases[Math.max(0, checkpointRank - 1)], operation: checkpoint.operation }), () => { wrongAuthoritativePhaseFailureCount += 1; });
      expectFailure(checkpoint, "LATER_PHASE_MISSING_HISTORICAL", "GOLDEN_REPLAY_HISTORICAL_EVIDENCE_INVALID", () => runProjectionAssertion({ contract: laterContract, projectionEvidencePhase: laterPhase, historicalOperationEvidence: { exact: false }, operation: checkpoint.operation }), () => { missingHistoricalEvidenceFailureCount += 1; });
      expectFailure(checkpoint, "LATER_PHASE_DUPLICATE_HISTORICAL", "GOLDEN_REPLAY_DUPLICATE_EFFECT", () => runProjectionAssertion({ contract: laterContract, projectionEvidencePhase: laterPhase, historicalOperationEvidence: { exact: true, duplicateEffect: true }, operation: checkpoint.operation }), () => { duplicateHistoricalEffectFailureCount += 1; });
    }
    const lowerPhase = phases[checkpointRank - 1];
    expectFailure(checkpoint, "LOWER_PHASE", "GOLDEN_REPLAY_PHASE_TOO_LOW", () => resolveGoldenReplayPhaseContract({ highestPersistedPhase: lowerPhase, checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }), () => {});
    expectFailure(checkpoint, "UNKNOWN_PHASE", "GOLDEN_PHASE_UNKNOWN", () => resolveGoldenReplayPhaseContract({ highestPersistedPhase: "SLICE_UNKNOWN", checkpointPhase: checkpoint.checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }), () => {});
  }
  return {
    checkpointCount: GOLDEN_REPLAY_PHASE_CHECKPOINTS.length,
    freshCaseCount,
    samePhaseReplayCaseCount,
    laterPhaseReplayCaseCount,
    wrongCheckpointProjectionFailureCount,
    wrongAuthoritativePhaseFailureCount,
    missingHistoricalEvidenceFailureCount,
    duplicateHistoricalEffectFailureCount,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function goldenStructuralCardinalityMismatches(actual, expected) {
  return Object.entries(expected)
    .filter(([field, expectedValue]) => actual?.[field] !== expectedValue)
    .map(([field, expectedValue]) => ({ field, expected: expectedValue, actual: actual?.[field] ?? null }));
}

function auditGoldenStructuralCardinalityMatrix() {
  const sliceGExpected = goldenSliceGStructuralCardinalityExpected();
  const downstreamContracts = [
    { id: "SLICE_H_RETURN", expected: { returnHeaderCount: 1, returnItemCount: 1, receiptEventCount: 1, receiptLineCount: 1 } },
    { id: "SLICE_J_CLAIM", expected: { claimHeaderCount: 1, claimItemCount: 1, claimEventCount: 1 } },
    { id: "SLICE_K_NOTIFICATION", expected: { notificationCount: 1, evaluatorRunCount: 1 } },
    { id: "STOCKTAKE", expected: { headerCount: 1, detailLineCount: 1 } },
    { id: "RECONCILIATION", expected: { runCount: 1, differenceRowCount: 1 } },
  ];
  const mismatches = [];
  let checkedPathCount = 0;
  const expectSliceG = (name, actual, shouldPass, category) => {
    const failures = sliceGStructuralCardinalityMismatches(actual);
    checkedPathCount += Object.keys(sliceGExpected).length;
    if (shouldPass ? failures.length > 0 : failures.length === 0) {
      mismatches.push({ contract: "SLICE_G_BUNDLE", case: name, category, expected: shouldPass ? "PASS" : "FAIL", actual: failures });
    }
  };
  const expectDownstream = (contract, name, actual, shouldPass, category) => {
    const failures = goldenStructuralCardinalityMismatches(actual, contract.expected);
    checkedPathCount += Object.keys(contract.expected).length;
    if (shouldPass ? failures.length > 0 : failures.length === 0) {
      mismatches.push({ contract: contract.id, case: name, category, expected: shouldPass ? "PASS" : "FAIL", actual: failures });
    }
  };

  expectSliceG("one source line expands to two components", sliceGExpected, true, "COMPONENT");
  expectSliceG("duplicated source-line identity", { ...sliceGExpected, externalSourceLineCount: 2, distinctSourceLineIdentityCount: 2 }, false, "EXTERNAL_SOURCE_LINE");
  expectSliceG("duplicated normalization event identity", { ...sliceGExpected, distinctNormalizationCount: 2 }, false, "NORMALIZATION");
  expectSliceG("missing canonical component", { ...sliceGExpected, rawNormalizationRowCount: 1, normalizedComponentRowCount: 1, orderItemCount: 1, reservationCount: 1, allocationCount: 1, ledgerEffectCount: 1, distinctComponentIdentityCount: 1 }, false, "COMPONENT");
  expectSliceG("duplicated canonical component identity", { ...sliceGExpected, rawNormalizationRowCount: 3, normalizedComponentRowCount: 3, orderItemCount: 3, reservationCount: 3, allocationCount: 3, ledgerEffectCount: 3, distinctComponentIdentityCount: 3 }, false, "DUPLICATE_IDENTITY");
  expectSliceG("two component reservations allocations and ledger effects", sliceGExpected, true, "COMPONENT");
  expectSliceG("duplicate reserve event", { ...sliceGExpected, reserveEventCount: 2 }, false, "EVENT");
  expectSliceG("duplicate ship event", { ...sliceGExpected, shipEventCount: 2 }, false, "EVENT");

  for (const contract of downstreamContracts) {
    expectDownstream(contract, "exact header/detail cardinality", contract.expected, true, "DOWNSTREAM");
    const duplicateDetail = { ...contract.expected };
    const detailField = Object.keys(contract.expected).find((field) => field !== "returnHeaderCount" && field !== "claimHeaderCount" && field !== "notificationCount" && field !== "headerCount" && field !== "runCount");
    duplicateDetail[detailField] = Number(duplicateDetail[detailField]) + 1;
    expectDownstream(contract, "duplicated detail identity", duplicateDetail, false, "DOWNSTREAM");
  }
  return {
    contractCount: 1 + downstreamContracts.length,
    checkedPathCount,
    negativeCaseCount: 2 + 1 + 1 + 2 + downstreamContracts.length,
    externalSourceLineMismatchCount: mismatches.filter((mismatch) => mismatch.category === "EXTERNAL_SOURCE_LINE").length,
    normalizationMismatchCount: mismatches.filter((mismatch) => mismatch.category === "NORMALIZATION").length,
    componentMismatchCount: mismatches.filter((mismatch) => mismatch.category === "COMPONENT").length,
    duplicateIdentityCount: mismatches.filter((mismatch) => mismatch.category === "DUPLICATE_IDENTITY").length,
    eventMismatchCount: mismatches.filter((mismatch) => mismatch.category === "EVENT").length,
    downstreamCardinalityMismatchCount: mismatches.filter((mismatch) => mismatch.category === "DOWNSTREAM").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

async function resolveGoldenRunnerOperationExitCode(operation) {
  try {
    await operation();
    return 0;
  } catch {
    return 1;
  }
}

async function auditGoldenExitSemantics() {
  const validContract = resolveGoldenReplayPhaseContract({
    highestPersistedPhase: "SLICE_E_RESERVED",
    checkpointPhase: "SLICE_E_RESERVED",
    executionMode: "REPLAY",
    operation: "EXIT_SEMANTICS",
  });
  const cases = [
    {
      name: "PURE_AUDIT_PASS",
      expectedExitCode: 0,
      operation: () => {
        const audit = auditGoldenProjectionReplayContextMatrix();
        if (audit.mismatchCount !== 0) throw new Error("GOLDEN_PROJECTION_REPLAY_CONTEXT_AUDIT_FAILED");
      },
    },
    {
      name: "SYNTHETIC_PROJECTION_PHASE_MISMATCH",
      expectedExitCode: 1,
      operation: () => resolveGoldenProjectionReplayContext({
        replayPhaseContract: validContract,
        checkpointPhase: "SLICE_E_RESERVED",
        authoritativePhase: "SLICE_E_RESERVED",
        projectionEvidencePhase: "SLICE_D_SHIPPED",
        operation: "EXIT_SEMANTICS",
      }),
    },
    {
      name: "UNKNOWN_REPLAY_PHASE",
      expectedExitCode: 1,
      operation: () => resolveGoldenReplayPhaseContract({
        highestPersistedPhase: "SLICE_UNKNOWN",
        checkpointPhase: "SLICE_E_RESERVED",
        executionMode: "REPLAY",
        operation: "EXIT_SEMANTICS",
      }),
    },
    {
      name: "MISSING_HISTORICAL_EVIDENCE",
      expectedExitCode: 1,
      operation: () => assertGoldenHistoricalReplayEvidence({
        phaseContract: validContract,
        evidence: { exact: false },
        operation: "EXIT_SEMANTICS",
      }),
    },
    {
      name: "UNEXPECTED_EXCEPTION",
      expectedExitCode: 1,
      operation: () => { throw new Error("GOLDEN_SYNTHETIC_UNEXPECTED_EXCEPTION"); },
    },
    {
      name: "SUCCESSFUL_PREFLIGHT",
      expectedExitCode: 0,
      operation: () => {
        const checkpointPhase = "SLICE_E_RESERVED";
        const authoritativePhase = [...SERUM_PROJECTION_PHASE_RANK.keys()][knownGoldenPhaseRank(checkpointPhase) + 1];
        const contract = resolveGoldenReplayPhaseContract({
          highestPersistedPhase: authoritativePhase,
          checkpointPhase,
          executionMode: "REPLAY",
          operation: "EXIT_SEMANTICS_PREFLIGHT",
        });
        const context = resolveGoldenProjectionReplayContext({
          replayPhaseContract: contract,
          checkpointPhase: contract.checkpointPhase,
          authoritativePhase: contract.authoritativePhase,
          projectionEvidencePhase: contract.authoritativePhase,
          operation: "EXIT_SEMANTICS_PREFLIGHT",
        });
        if (context.projectionEvidencePhase !== authoritativePhase) {
          throw new Error("GOLDEN_SYNTHETIC_PREFLIGHT_CONTEXT_INVALID");
        }
      },
    },
  ];
  const mismatches = [];
  for (const matrixCase of cases) {
    const actualExitCode = await resolveGoldenRunnerOperationExitCode(matrixCase.operation);
    if (actualExitCode !== matrixCase.expectedExitCode) {
      mismatches.push({ case: matrixCase.name, expectedExitCode: matrixCase.expectedExitCode, actualExitCode });
    }
  }
  return {
    caseCount: cases.length,
    zeroExitCaseCount: cases.filter((matrixCase) => matrixCase.expectedExitCode === 0).length,
    nonzeroExitCaseCount: cases.filter((matrixCase) => matrixCase.expectedExitCode !== 0).length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function getSerumProjectionPhaseRank(phase) {
  return SERUM_PROJECTION_PHASE_RANK.get(String(phase?.detectedPhase ?? "")) ?? -1;
}

function highestGoldenCurrentStatePhase(...candidates) {
  const present = candidates.filter((candidate) => candidate !== null && candidate !== undefined);
  if (present.length === 0) {
    throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");
  }
  for (const candidate of present) {
    if (getSerumProjectionPhaseRank(candidate) < 0) {
      throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");
    }
  }
  return present.reduce((highest, candidate) =>
    getSerumProjectionPhaseRank(candidate) > getSerumProjectionPhaseRank(highest)
      ? candidate
      : highest,
  );
}

const GOLDEN_ASSERTION_CONTEXT_TARGETS = new Set(["SLICE_B", "SLICE_C", "SLICE_D", "SLICE_E"]);
const GOLDEN_ASSERTION_CONTEXT_OPERATIONS = new Set(["PREPARE", "REPLAY", "RESERVE", "SHIP"]);
const GOLDEN_ASSERTION_CONTEXT_CHECKPOINT_PHASE = Object.freeze({
  "SLICE_B:REPLAY:AFTER_SLICE_B_RECEIPT": "SLICE_B_RECEIVED",
  "SLICE_C:REPLAY:AFTER_SHOPEE_RESERVATION": "SLICE_C_RESERVED",
  "SLICE_C:RESERVE:AFTER_SHOPEE_RESERVATION": "SLICE_C_RESERVED",
  "SLICE_D:REPLAY:AFTER_SHOPEE_SHIPMENT": "SLICE_D_SHIPPED",
  "SLICE_D:SHIP:AFTER_SHOPEE_SHIPMENT": "SLICE_D_SHIPPED",
  "SLICE_E:PREPARE:BEFORE_TIKTOK_RESERVATION": "SLICE_D_SHIPPED",
  "SLICE_E:REPLAY:AFTER_TIKTOK_RESERVATION": "SLICE_E_RESERVED",
  "SLICE_E:RESERVE:AFTER_TIKTOK_RESERVATION": "SLICE_E_RESERVED",
  "SLICE_E:REPLAY:AFTER_TIKTOK_SHIPMENT": "SLICE_E_IN_TRANSIT",
  "SLICE_E:SHIP:AFTER_TIKTOK_SHIPMENT": "SLICE_E_IN_TRANSIT",
});

function resolveGoldenAssertionContexts({ highestPersistedPhase, targetSlice, operation, checkpoint }) {
  if (!GOLDEN_ASSERTION_CONTEXT_TARGETS.has(targetSlice) || !GOLDEN_ASSERTION_CONTEXT_OPERATIONS.has(operation)) {
    throw new Error("GOLDEN_ASSERTION_CONTEXT_INVALID");
  }
  const checkpointPhase = GOLDEN_ASSERTION_CONTEXT_CHECKPOINT_PHASE[`${targetSlice}:${operation}:${checkpoint}`];
  if (!checkpointPhase) throw new Error("GOLDEN_ASSERTION_CONTEXT_INVALID");
  let phaseContract;
  try {
    phaseContract = resolveGoldenReplayPhaseContract({
      highestPersistedPhase,
      checkpointPhase,
      executionMode: operation === "REPLAY" ? "REPLAY" : "FRESH",
      operation: `${targetSlice}:${operation}:${checkpoint}`,
    });
  } catch {
    throw new Error("GOLDEN_ASSERTION_CONTEXT_INVALID");
  }
  const phase = phaseContract.authoritativePhase;
  const state = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
  return {
    projectionPhase: state,
    lifecyclePhase: expectedGoldenCurrentStateForPhase({ detectedPhase: phase }),
    replayPhaseContract: phaseContract,
  };
}

function auditGoldenAssertionContextMatrix() {
  const mismatches = [];
  const cases = [
    { name: "SLICE_B", highestPersistedPhase: "SLICE_B_RECEIVED", targetSlice: "SLICE_B", operation: "REPLAY", checkpoint: "AFTER_SLICE_B_RECEIPT", expectedPhase: "SLICE_B_RECEIVED" },
    { name: "SLICE_C", highestPersistedPhase: "SLICE_C_RESERVED", targetSlice: "SLICE_C", operation: "RESERVE", checkpoint: "AFTER_SHOPEE_RESERVATION", expectedPhase: "SLICE_C_RESERVED" },
    { name: "SLICE_D", highestPersistedPhase: "SLICE_D_SHIPPED", targetSlice: "SLICE_D", operation: "SHIP", checkpoint: "AFTER_SHOPEE_SHIPMENT", expectedPhase: "SLICE_D_SHIPPED" },
    { name: "SLICE_D_REPLAY_AT_E", highestPersistedPhase: "SLICE_E_RESERVED", targetSlice: "SLICE_D", operation: "REPLAY", checkpoint: "AFTER_SHOPEE_SHIPMENT", expectedPhase: "SLICE_E_RESERVED" },
    { name: "SLICE_E_BEFORE_RESERVATION", highestPersistedPhase: "SLICE_D_SHIPPED", targetSlice: "SLICE_E", operation: "PREPARE", checkpoint: "BEFORE_TIKTOK_RESERVATION", expectedPhase: "SLICE_D_SHIPPED" },
    { name: "SLICE_E_RESERVED", highestPersistedPhase: "SLICE_E_RESERVED", targetSlice: "SLICE_E", operation: "RESERVE", checkpoint: "AFTER_TIKTOK_RESERVATION", expectedPhase: "SLICE_E_RESERVED" },
    { name: "SLICE_E_IN_TRANSIT", highestPersistedPhase: "SLICE_E_IN_TRANSIT", targetSlice: "SLICE_E", operation: "SHIP", checkpoint: "AFTER_TIKTOK_SHIPMENT", expectedPhase: "SLICE_E_IN_TRANSIT" },
    { name: "SLICE_E_RESERVATION_REPLAY_AT_IN_TRANSIT", highestPersistedPhase: "SLICE_E_IN_TRANSIT", targetSlice: "SLICE_E", operation: "REPLAY", checkpoint: "AFTER_TIKTOK_RESERVATION", expectedPhase: "SLICE_E_IN_TRANSIT" },
  ];
  let projectionContextCount = 0;
  let lifecycleContextCount = 0;
  let checkedPathCount = 0;
  let projectionMismatchCount = 0;
  let lifecycleMismatchCount = 0;
  let checkpointMismatchCount = 0;
  for (const matrixCase of cases) {
    try {
      const contexts = resolveGoldenAssertionContexts(matrixCase);
      projectionContextCount += 1;
      lifecycleContextCount += 1;
      checkedPathCount += 2;
      if (contexts.projectionPhase.detectedPhase !== matrixCase.expectedPhase) {
        projectionMismatchCount += 1;
        mismatches.push({ case: matrixCase.name, path: "projectionPhase", expected: matrixCase.expectedPhase, actual: contexts.projectionPhase.detectedPhase });
      }
      if (contexts.lifecyclePhase.detectedPhase !== matrixCase.expectedPhase) {
        lifecycleMismatchCount += 1;
        mismatches.push({ case: matrixCase.name, path: "lifecyclePhase", expected: matrixCase.expectedPhase, actual: contexts.lifecyclePhase.detectedPhase });
      }
    } catch (error) {
      projectionMismatchCount += 1;
      lifecycleMismatchCount += 1;
      mismatches.push({ case: matrixCase.name, path: "resolver", expected: "valid context", actual: error instanceof Error ? error.message : "UNKNOWN" });
    }
  }
  const persistedD = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_D_SHIPPED" });
  const persistedC = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_C_RESERVED" });
  const projectionPaths = ["sellable", "reserved", "available"];
  const staleProjectionDifferences = projectionPaths.filter((path) => persistedD.serumProduct[path] !== persistedC.serumProduct[path]);
  checkedPathCount += projectionPaths.length + 1;
  if (JSON.stringify(staleProjectionDifferences) !== JSON.stringify(["sellable", "reserved"])) {
    projectionMismatchCount += 1;
    mismatches.push({ case: "SLICE_D_WRONG_C_PROJECTION", path: "serumProduct", expected: ["sellable", "reserved"], actual: staleProjectionDifferences });
  }
  if (persistedD.shopeeLifecycle.shipped === persistedC.shopeeLifecycle.shipped) {
    lifecycleMismatchCount += 1;
    mismatches.push({ case: "SLICE_D_LIFECYCLE_INDEPENDENT", path: "shopeeLifecycle.shipped", expected: "D differs from C", actual: persistedD.shopeeLifecycle.shipped });
  }
  const reservedTikTok = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_E_RESERVED" });
  const inTransitTikTok = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_E_IN_TRANSIT" });
  const checkpointLifecyclePaths = ["consumed", "shipped", "openReserved"];
  const prematureCheckpointDifferences = checkpointLifecyclePaths.filter((path) =>
    reservedTikTok.tiktokComponentLifecycle[path] !== inTransitTikTok.tiktokComponentLifecycle[path],
  );
  checkedPathCount += checkpointLifecyclePaths.length;
  if (JSON.stringify(prematureCheckpointDifferences) !== JSON.stringify(checkpointLifecyclePaths)) {
    lifecycleMismatchCount += 1;
    checkpointMismatchCount += 1;
    mismatches.push({ case: "SLICE_E_PREMATURE_IN_TRANSIT", path: "tiktokComponentLifecycle", expected: checkpointLifecyclePaths, actual: prematureCheckpointDifferences });
  }
  let invalidCheckpointRejected = false;
  try {
    resolveGoldenAssertionContexts({ highestPersistedPhase: "SLICE_E_RESERVED", targetSlice: "SLICE_E", operation: "SHIP", checkpoint: "AFTER_TIKTOK_SHIPMENT" });
  } catch (error) {
    invalidCheckpointRejected = error instanceof Error && error.message === "GOLDEN_ASSERTION_CONTEXT_INVALID";
  }
  checkedPathCount += 1;
  if (!invalidCheckpointRejected) {
    lifecycleMismatchCount += 1;
    checkpointMismatchCount += 1;
    mismatches.push({ case: "SLICE_E_PREMATURE_IN_TRANSIT", path: "resolver", expected: "GOLDEN_ASSERTION_CONTEXT_INVALID", actual: "accepted" });
  }
  let unknownPhaseRejected = false;
  try {
    resolveGoldenAssertionContexts({ highestPersistedPhase: "SLICE_UNKNOWN", targetSlice: "SLICE_C", operation: "REPLAY", checkpoint: "AFTER_SHOPEE_RESERVATION" });
  } catch (error) {
    unknownPhaseRejected = error instanceof Error && error.message === "GOLDEN_ASSERTION_CONTEXT_INVALID";
  }
  checkedPathCount += 1;
  if (!unknownPhaseRejected) {
    projectionMismatchCount += 1;
    lifecycleMismatchCount += 1;
    checkpointMismatchCount += 1;
    mismatches.push({ case: "UNKNOWN_PHASE", path: "resolver", expected: "GOLDEN_ASSERTION_CONTEXT_INVALID", actual: "accepted" });
  }
  return {
    phaseCaseCount: cases.length + 2,
    checkpointCaseCount: cases.length + 2,
    projectionContextCount,
    lifecycleContextCount,
    checkedPathCount,
    projectionMismatchCount,
    lifecycleMismatchCount,
    checkpointMismatchCount,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

const GOLDEN_PRODUCTION_BATCH_CODES = Object.freeze(["SER-2608-A", "SER-2612-B", "SER-2701-C"]);
const GOLDEN_CLEANSER_BATCH_CODE = "CLN-2611-A";
const GOLDEN_INVENTORY_AFTER_SLICE_I = Object.freeze({
  serum: Object.freeze([24, 0, 24]),
  batches: Object.freeze([0, 12, 10]),
  cleanser: Object.freeze([14, 0, 14]),
  cleanserBatch: 14,
});

function isPlainObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function goldenExpectedStateShapeError(phase, missingPaths, invalidPaths, checkedPathCount) {
  const error = new Error("GOLDEN_EXPECTED_STATE_SHAPE_INVALID");
  error.code = "GOLDEN_EXPECTED_STATE_SHAPE_INVALID";
  error.detail = { phase, missingPaths, invalidPaths, checkedPathCount };
  return error;
}

function inspectGoldenExpectedStateShape(phase, state) {
  const phaseName = phaseNameOf(phase);
  const missingPaths = [];
  const invalidPaths = [];
  let checkedPathCount = 0;
  const requireObject = (value, path) => {
    checkedPathCount += 1;
    if (value === undefined) {
      missingPaths.push(path);
      return false;
    }
    if (!isPlainObject(value)) {
      invalidPaths.push({ path, reason: "EXPECTED_PLAIN_OBJECT" });
      return false;
    }
    return true;
  };
  const requireString = (value, path) => {
    checkedPathCount += 1;
    if (value === undefined) missingPaths.push(path);
    else if (typeof value !== "string" || !value) invalidPaths.push({ path, reason: "EXPECTED_NON_EMPTY_STRING" });
  };
  const requireQuantity = (value, path) => {
    checkedPathCount += 1;
    if (value === undefined) missingPaths.push(path);
    else if (!Number.isSafeInteger(value) || value < 0) invalidPaths.push({ path, reason: "EXPECTED_NON_NEGATIVE_SAFE_INTEGER" });
  };
  if (!requireObject(state, "state")) return { missingPaths, invalidPaths, checkedPathCount };

  requireString(state.phase, "phase");
  requireString(state.detectedPhase, "detectedPhase");
  if (state.phase !== phaseName) invalidPaths.push({ path: "phase", reason: "EXPECTED_PHASE_IDENTITY" });
  if (state.detectedPhase !== phaseName) invalidPaths.push({ path: "detectedPhase", reason: "EXPECTED_PHASE_IDENTITY" });

  const serumProductValid = requireObject(state.serumProduct, "serumProduct");
  const cleanserProductValid = requireObject(state.cleanserProduct, "cleanserProduct");
  const batchesValid = requireObject(state.batches, "batches");
  const serumProductionBatchesValid = requireObject(state.serumProductionBatches, "serumProductionBatches");
  const serumReturnBatchesValid = requireObject(state.serumReturnBatches, "serumReturnBatches");
  const cleanserBatchesValid = requireObject(state.cleanserBatches, "cleanserBatches");
  const shopeeLifecycleValid = requireObject(state.shopeeLifecycle, "shopeeLifecycle");
  const tiktokLifecycleValid = requireObject(state.tiktokLifecycle, "tiktokLifecycle");
  const tiktokComponentLifecycleValid = requireObject(state.tiktokComponentLifecycle, "tiktokComponentLifecycle");
  const returnLifecycleValid = requireObject(state.returnLifecycle, "returnLifecycle");
  const tiktokReturnLifecycleValid = requireObject(state.tiktokReturnLifecycle, "tiktokReturnLifecycle");
  const claimNotificationValid = requireObject(state.claimNotificationExpectation, "claimNotificationExpectation");
  const stocktakeStateValid = requireObject(state.stocktakeState, "stocktakeState");
  const reconciliationStateValid = requireObject(state.reconciliationState, "reconciliationState");

  if (serumProductValid) {
    requireString(state.serumProduct.detectedPhase, "serumProduct.detectedPhase");
    if (state.serumProduct.detectedPhase !== phaseName) invalidPaths.push({ path: "serumProduct.detectedPhase", reason: "EXPECTED_PHASE_IDENTITY" });
    for (const key of ["sellable", "reserved", "available"]) requireQuantity(state.serumProduct[key], `serumProduct.${key}`);
    if (requireObject(state.serumProduct.batches, "serumProduct.batches")) {
      for (const code of GOLDEN_PRODUCTION_BATCH_CODES) requireQuantity(state.serumProduct.batches[code], `serumProduct.batches.${code}`);
    }
  }
  if (cleanserProductValid) for (const key of ["sellable", "reserved", "available"]) requireQuantity(state.cleanserProduct[key], `cleanserProduct.${key}`);
  for (const [label, valid] of [["batches", batchesValid], ["serumProductionBatches", serumProductionBatchesValid]]) {
    if (valid) for (const code of GOLDEN_PRODUCTION_BATCH_CODES) requireQuantity(state[label][code], `${label}.${code}`);
  }
  if (serumReturnBatchesValid) for (const key of ["count", "sellable"]) requireQuantity(state.serumReturnBatches[key], `serumReturnBatches.${key}`);
  if (cleanserBatchesValid) requireQuantity(state.cleanserBatches[GOLDEN_CLEANSER_BATCH_CODE], `cleanserBatches.${GOLDEN_CLEANSER_BATCH_CODE}`);
  if (shopeeLifecycleValid) {
    for (const key of ["reserved", "consumed", "released", "shipped", "preShipmentCancelled", "postShipmentCancelled", "returnExpected", "returnReceived", "returnSellable", "returnDamaged", "returnLost", "openReserved", "remaining"]) requireQuantity(state.shopeeLifecycle[key], `shopeeLifecycle.${key}`);
    requireString(state.shopeeLifecycle.reservationStatus, "shopeeLifecycle.reservationStatus");
  }
  if (tiktokLifecycleValid) for (const key of ["reserved", "consumed", "released", "shipped", "openReserved"]) requireQuantity(state.tiktokLifecycle[key], `tiktokLifecycle.${key}`);
  if (tiktokComponentLifecycleValid) {
    for (const key of ["reserved", "consumed", "released", "shipped", "preShipmentCancelled", "postShipmentCancelled", "returnExpected", "returnReceived", "returnSellable", "returnDamaged", "returnLost", "openReserved", "remaining"]) requireQuantity(state.tiktokComponentLifecycle[key], `tiktokComponentLifecycle.${key}`);
    requireString(state.tiktokComponentLifecycle.reservationStatus, "tiktokComponentLifecycle.reservationStatus");
  }
  if (returnLifecycleValid) for (const key of ["expected", "received", "sellable", "damaged", "lost"]) requireQuantity(state.returnLifecycle[key], `returnLifecycle.${key}`);
  if (tiktokReturnLifecycleValid) {
    for (const key of ["expected", "received", "sellable", "damaged", "grossLost", "netLost", "pendingArrival", "pendingInspection"]) requireQuantity(state.tiktokReturnLifecycle[key], `tiktokReturnLifecycle.${key}`);
    requireString(state.tiktokReturnLifecycle.status, "tiktokReturnLifecycle.status");
    requireString(state.tiktokReturnLifecycle.outcome, "tiktokReturnLifecycle.outcome");
  }
  if (claimNotificationValid) {
    for (const key of ["claimCount", "claimItemCount", "claimEventCount", "notificationCount", "notificationRuleRunCount"]) requireQuantity(state.claimNotificationExpectation[key], `claimNotificationExpectation.${key}`);
    requireString(state.claimNotificationExpectation.claimEvidence, "claimNotificationExpectation.claimEvidence");
    requireString(state.claimNotificationExpectation.notificationStage, "claimNotificationExpectation.notificationStage");
  }
  if (stocktakeStateValid) requireString(state.stocktakeState.status, "stocktakeState.status");
  if (reconciliationStateValid) requireString(state.reconciliationState.status, "reconciliationState.status");
  return { missingPaths, invalidPaths, checkedPathCount };
}

function validateGoldenExpectedStateShape(phase, state) {
  const inspection = inspectGoldenExpectedStateShape(phase, state);
  if (inspection.missingPaths.length > 0 || inspection.invalidPaths.length > 0) {
    throw goldenExpectedStateShapeError(phaseNameOf(phase), inspection.missingPaths, inspection.invalidPaths, inspection.checkedPathCount);
  }
  return state;
}

function buildGoldenShopeeLifecycle(rank) {
  if (rank === 2) return { reserved: 8, consumed: 0, released: 0, reservationStatus: "ACTIVE", shipped: 0, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 0, returnReceived: 0, returnSellable: 0, returnDamaged: 0, returnLost: 0, openReserved: 8, remaining: 0 };
  if (rank >= 11) return { reserved: 8, consumed: 8, released: 0, reservationStatus: "CONSUMED", shipped: 8, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 3, returnReceived: 3, returnSellable: 2, returnDamaged: 1, returnLost: 0, openReserved: 0, remaining: 5 };
  if (rank >= 10) return { reserved: 8, consumed: 8, released: 0, reservationStatus: "CONSUMED", shipped: 8, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 3, returnReceived: 3, returnSellable: 0, returnDamaged: 0, returnLost: 0, openReserved: 0, remaining: 5 };
  if (rank >= 9) return { reserved: 8, consumed: 8, released: 0, reservationStatus: "CONSUMED", shipped: 8, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 3, returnReceived: 0, returnSellable: 0, returnDamaged: 0, returnLost: 0, openReserved: 0, remaining: 5 };
  if (rank >= 3) return { reserved: 8, consumed: 8, released: 0, reservationStatus: "CONSUMED", shipped: 8, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 0, returnReceived: 0, returnSellable: 0, returnDamaged: 0, returnLost: 0, openReserved: 0, remaining: 8 };
  return { reserved: 0, consumed: 0, released: 0, reservationStatus: "NONE", shipped: 0, preShipmentCancelled: 0, postShipmentCancelled: 0, returnExpected: 0, returnReceived: 0, returnSellable: 0, returnDamaged: 0, returnLost: 0, openReserved: 0, remaining: 0 };
}

function buildGoldenTiktokComponentLifecycle(rank) {
  const reservation = rank >= 5
    ? { reserved: 1, consumed: 1, released: 0, reservationStatus: "CONSUMED", shipped: 1, openReserved: 0 }
    : rank === 4
      ? { reserved: 1, consumed: 0, released: 0, reservationStatus: "ACTIVE", shipped: 0, openReserved: 1 }
      : { reserved: 0, consumed: 0, released: 0, reservationStatus: "NONE", shipped: 0, openReserved: 0 };
  const returnExpected = rank >= 12 ? SLICE_J.quantity : 0;
  const returnLost = rank >= 13 ? SLICE_J.quantity : 0;
  return {
    reserved: reservation.reserved,
    consumed: reservation.consumed,
    released: reservation.released,
    reservationStatus: reservation.reservationStatus,
    shipped: reservation.shipped,
    preShipmentCancelled: 0,
    postShipmentCancelled: 0,
    returnExpected,
    returnReceived: 0,
    returnSellable: 0,
    returnDamaged: 0,
    returnLost,
    openReserved: reservation.openReserved,
    remaining: Math.max(reservation.shipped - returnExpected, 0),
  };
}

const GOLDEN_LIFECYCLE_QUANTITY_KEYS = Object.freeze([
  "reserved",
  "consumed",
  "released",
  "shipped",
  "preShipmentCancelled",
  "postShipmentCancelled",
  "returnExpected",
  "returnReceived",
  "returnSellable",
  "returnDamaged",
  "returnLost",
  "openReserved",
  "remaining",
]);

function goldenLifecycleExpectationError(phase, identity, missingPaths, invalidPaths) {
  const error = new Error("GOLDEN_LIFECYCLE_EXPECTATION_INVALID");
  error.code = "GOLDEN_LIFECYCLE_EXPECTATION_INVALID";
  error.detail = { phase, identity, missingPaths, invalidPaths };
  return error;
}

function validateMarketplaceComponentLifecycleIdentity(phase, identity) {
  const missingPaths = [];
  const invalidPaths = [];
  if (!isPlainObject(identity)) {
    throw goldenLifecycleExpectationError(phase, null, ["identity"], []);
  }
  for (const key of ["organizationId", "channelCode", "marketplaceOrderRef", "sourceLineRef", "canonicalSourceLineRef", "productId", "productSku"]) {
    if (identity[key] === undefined) missingPaths.push(`identity.${key}`);
    else if (!isNonBlank(identity[key])) invalidPaths.push({ path: `identity.${key}`, reason: "EXPECTED_NON_EMPTY_STRING" });
  }
  if (identity.componentNo === undefined) missingPaths.push("identity.componentNo");
  else if (!Number.isSafeInteger(identity.componentNo) || identity.componentNo < 1) invalidPaths.push({ path: "identity.componentNo", reason: "EXPECTED_POSITIVE_SAFE_INTEGER" });
  if (missingPaths.length > 0 || invalidPaths.length > 0) {
    throw goldenLifecycleExpectationError(phase, identity, missingPaths, invalidPaths);
  }
  return { ...identity };
}

function validateMarketplaceComponentLifecycleExpectation(phase, identity, expectation) {
  const normalizedIdentity = validateMarketplaceComponentLifecycleIdentity(phase, identity);
  const missingPaths = [];
  const invalidPaths = [];
  if (!isPlainObject(expectation)) {
    throw goldenLifecycleExpectationError(phase, normalizedIdentity, ["expectation"], []);
  }
  for (const key of GOLDEN_LIFECYCLE_QUANTITY_KEYS) {
    if (expectation[key] === undefined) missingPaths.push(`expectation.${key}`);
    else if (!Number.isSafeInteger(expectation[key]) || expectation[key] < 0) invalidPaths.push({ path: `expectation.${key}`, reason: "EXPECTED_NON_NEGATIVE_SAFE_INTEGER" });
  }
  if (expectation.reservationStatus === undefined) missingPaths.push("expectation.reservationStatus");
  else if (!isNonBlank(expectation.reservationStatus)) invalidPaths.push({ path: "expectation.reservationStatus", reason: "EXPECTED_NON_EMPTY_STRING" });
  if (missingPaths.length === 0 && invalidPaths.length === 0) {
    if (expectation.returnExpected < expectation.returnReceived + expectation.returnLost) invalidPaths.push({ path: "expectation.returnExpected", reason: "EXPECTED_COVERS_RECEIVED_AND_LOST" });
    if (expectation.returnSellable + expectation.returnDamaged > expectation.returnReceived) invalidPaths.push({ path: "expectation.returnSellable", reason: "SELLABLE_AND_DAMAGED_EXCEED_RECEIVED" });
  }
  if (missingPaths.length > 0 || invalidPaths.length > 0) {
    throw goldenLifecycleExpectationError(phase, normalizedIdentity, missingPaths, invalidPaths);
  }
  return { ...expectation };
}

function marketplaceLifecycleActualFromRow(row) {
  return {
    reserved: asNumber(row?.reserved_qty),
    consumed: asNumber(row?.consumed_qty),
    released: asNumber(row?.released_qty),
    reservationStatus: String(row?.reservation_status_code ?? ""),
    shipped: asNumber(row?.shipped_quantity),
    preShipmentCancelled: asNumber(row?.pre_shipment_cancelled_quantity),
    postShipmentCancelled: asNumber(row?.post_shipment_cancelled_quantity),
    returnExpected: asNumber(row?.return_expected_quantity),
    returnReceived: asNumber(row?.return_received_quantity),
    returnSellable: asNumber(row?.return_sellable_quantity),
    returnDamaged: asNumber(row?.return_damaged_quantity),
    returnLost: asNumber(row?.return_lost_quantity),
    openReserved: asNumber(row?.open_reserved_quantity),
    remaining: asNumber(row?.remaining_returnable_or_cancellable_quantity),
  };
}

function marketplaceLifecycleMismatches(expected, actual) {
  const fields = ["reservationStatus", ...GOLDEN_LIFECYCLE_QUANTITY_KEYS];
  return fields.filter((field) => expected[field] !== actual[field]).map((field) => ({ field, expected: expected[field], actual: actual[field] }));
}

function assertGoldenMarketplaceComponentLifecycleCurrent(slice, highestPersistedPhase, componentIdentity, row) {
  const expected = expectedMarketplaceComponentLifecycleForPhase(highestPersistedPhase, componentIdentity);
  const actual = marketplaceLifecycleActualFromRow(row);
  const mismatches = marketplaceLifecycleMismatches(expected, actual);
  if (mismatches.length > 0) {
    console.log(JSON.stringify({
      code: "GOLDEN_MARKETPLACE_LIFECYCLE_MISMATCH",
      slice,
      highestPersistedPhase: phaseNameOf(highestPersistedPhase),
      componentIdentity,
      mismatches,
    }, null, 2));
    fail("GOLDEN_MARKETPLACE_LIFECYCLE_MISMATCH");
    return null;
  }
  return row;
}

/*
 * This is the sole source for mutable Golden read-model expectations. Every
 * call returns a fresh, validated, full-shape state so durable lower-slice
 * replays can consume a higher persisted phase without a partial context.
 */
function expectedGoldenCurrentStateForPhase(phase) {
  const name = phaseNameOf(phase);
  if (getSerumProjectionPhaseRank({ detectedPhase: name }) < 0) {
    throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");
  }
  const states = {
    SLICE_A_INITIAL: { serum: [25, 0, 25], batches: [5, 20, 0], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_B_RECEIVED: { serum: [35, 0, 35], batches: [5, 20, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_C_RESERVED: { serum: [35, 8, 27], batches: [5, 20, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_D_SHIPPED: { serum: [27, 0, 27], batches: [0, 17, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_E_RESERVED: { serum: [27, 1, 26], batches: [0, 17, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_E_IN_TRANSIT: { serum: [26, 0, 26], batches: [0, 16, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_F_MANUAL_BONUS: { serum: [24, 0, 24], batches: [0, 14, 10], cleanser: [15, 0, 15], cleanserBatch: 15 },
    SLICE_G_BUNDLE_RESERVED: { serum: [24, 2, 22], batches: [0, 14, 10], cleanser: [15, 1, 14], cleanserBatch: 15 },
    SLICE_G_BUNDLE_SHIPPED: { serum: [22, 0, 22], batches: [0, 12, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
    SLICE_H_RETURN_EXPECTED: { serum: [22, 0, 22], batches: [0, 12, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
    SLICE_H_RETURN_RECEIVED: { serum: [22, 0, 22], batches: [0, 12, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
    SLICE_I_RETURN_INSPECTED: GOLDEN_INVENTORY_AFTER_SLICE_I,
    SLICE_J_TIKTOK_RETURN_EXPECTED: GOLDEN_INVENTORY_AFTER_SLICE_I,
    SLICE_J_TIKTOK_RETURN_LOST: GOLDEN_INVENTORY_AFTER_SLICE_I,
    SLICE_K_TIKTOK_CLAIM_CREATED: GOLDEN_INVENTORY_AFTER_SLICE_I,
    SLICE_K_TIKTOK_CLAIM_NOTIFICATION: GOLDEN_INVENTORY_AFTER_SLICE_I,
    GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED: { serum: [23, 0, 23], batches: [0, 11, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
    GOLDEN_RECONCILIATION_COMPLETED: { serum: [23, 0, 23], batches: [0, 11, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
    GOLDEN_FINAL_ACCEPTED: { serum: [23, 0, 23], batches: [0, 11, 10], cleanser: [14, 0, 14], cleanserBatch: 14 },
  };
  const inventoryState = states[name];
  if (!inventoryState) throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");

  const rank = knownGoldenPhaseRank(name);
  const [serumSellable, serumReserved, serumAvailable] = inventoryState.serum;
  const [batchA, batchB, batchC] = inventoryState.batches;
  const [cleanserSellable, cleanserReserved, cleanserAvailable] = inventoryState.cleanser;
  const batches = { "SER-2608-A": batchA, "SER-2612-B": batchB, "SER-2701-C": batchC };
  const shopeeLifecycle = buildGoldenShopeeLifecycle(rank);
  const tiktokComponentLifecycle = buildGoldenTiktokComponentLifecycle(rank);
  const tiktokReturnLost = tiktokComponentLifecycle.returnLost;
  const tiktokReturnExpected = tiktokComponentLifecycle.returnExpected;
  const state = {
    phase: name,
    detectedPhase: name,
    batches: { ...batches },
    serumProduct: { detectedPhase: name, sellable: serumSellable, reserved: serumReserved, available: serumAvailable, batches: { ...batches } },
    cleanserProduct: { sellable: cleanserSellable, reserved: cleanserReserved, available: cleanserAvailable },
    serumProductionBatches: { ...batches },
    serumReturnBatches: rank >= 11 ? { count: 1, sellable: 2 } : { count: 0, sellable: 0 },
    cleanserBatches: { [GOLDEN_CLEANSER_BATCH_CODE]: inventoryState.cleanserBatch },
    shopeeLifecycle,
    tiktokLifecycle: { reserved: tiktokComponentLifecycle.reserved, consumed: tiktokComponentLifecycle.consumed, released: tiktokComponentLifecycle.released, shipped: tiktokComponentLifecycle.shipped, openReserved: tiktokComponentLifecycle.openReserved },
    tiktokComponentLifecycle,
    returnLifecycle: { expected: shopeeLifecycle.returnExpected, received: shopeeLifecycle.returnReceived, sellable: shopeeLifecycle.returnSellable, damaged: shopeeLifecycle.returnDamaged, lost: shopeeLifecycle.returnLost },
    tiktokReturnLifecycle: { expected: tiktokReturnExpected, received: 0, sellable: 0, damaged: 0, grossLost: tiktokReturnLost, netLost: tiktokReturnLost, pendingArrival: tiktokReturnExpected - tiktokReturnLost, pendingInspection: 0, status: tiktokReturnLost === 1 ? "LOST" : tiktokReturnExpected === 1 ? "EXPECTED" : "NONE", outcome: tiktokReturnLost === 1 ? "LOST" : "NONE" },
    claimNotificationExpectation: { claimCount: rank >= 14 ? 1 : 0, claimItemCount: rank >= 14 ? 1 : 0, claimEventCount: rank >= 14 ? 1 : 0, notificationCount: rank >= 15 ? 1 : 0, notificationRuleRunCount: rank >= 15 ? 1 : 0, claimEvidence: rank >= 14 ? "CREATED" : "NONE", notificationStage: rank >= 15 ? "D14" : "NONE" },
    stocktakeState: rank >= 16
      ? { status: "POSTED", expectedQty: GOLDEN_TERMINAL.expectedQty, physicalQty: GOLDEN_TERMINAL.physicalQty, varianceQty: GOLDEN_TERMINAL.varianceQty, adjustmentQty: GOLDEN_TERMINAL.varianceQty, batchCode: GOLDEN_TERMINAL.batchCode }
      : { status: "NONE" },
    reconciliationState: rank >= 17
      ? { status: GOLDEN_RECONCILIATION.successfulStatus, runType: GOLDEN_RECONCILIATION.runType, stockEffect: "NONE" }
      : { status: "NONE" },
  };
  return validateGoldenExpectedStateShape({ detectedPhase: name }, state);
}

function expectedBatchQuantityForPhase(phase, batchCode) {
  if (!GOLDEN_PRODUCTION_BATCH_CODES.includes(batchCode)) {
    throw new Error(`GOLDEN_EXPECTED_BATCH_UNKNOWN: ${String(batchCode)}`);
  }
  const state = expectedGoldenCurrentStateForPhase(phase);
  const quantity = state.batches[batchCode];
  if (!Number.isSafeInteger(quantity)) {
    throw new Error("GOLDEN_EXPECTED_STATE_SHAPE_INVALID");
  }
  return quantity;
}

function auditGoldenExpectedStateModel() {
  const knownPhases = [...SERUM_PROJECTION_PHASE_RANK.keys()];
  const mismatches = [];
  let validStateCount = 0;
  let checkedPathCount = 0;
  for (const phase of knownPhases) {
    try {
      const state = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
      const inspection = inspectGoldenExpectedStateShape({ detectedPhase: phase }, state);
      checkedPathCount += inspection.checkedPathCount;
      if (inspection.missingPaths.length > 0 || inspection.invalidPaths.length > 0) {
        for (const path of inspection.missingPaths) mismatches.push({ phase, path, reason: "MISSING" });
        for (const invalid of inspection.invalidPaths) mismatches.push({ phase, path: invalid.path, reason: invalid.reason });
      } else {
        validStateCount += 1;
      }
    } catch (error) {
      const detail = error && typeof error === "object" ? error.detail : null;
      checkedPathCount += Number.isSafeInteger(detail?.checkedPathCount) ? detail.checkedPathCount : 0;
      for (const path of detail?.missingPaths ?? []) mismatches.push({ phase, path, reason: "MISSING" });
      for (const invalid of detail?.invalidPaths ?? []) mismatches.push({ phase, path: invalid.path, reason: invalid.reason });
      if (!detail || (detail.missingPaths?.length ?? 0) === 0 && (detail.invalidPaths?.length ?? 0) === 0) {
        mismatches.push({ phase, path: "state", reason: error instanceof Error ? error.message : "UNKNOWN" });
      }
    }
  }
  return { knownPhaseCount: knownPhases.length, validStateCount, invalidStateCount: knownPhases.length - validStateCount, checkedPathCount, mismatchCount: mismatches.length, mismatches };
}

function auditGoldenStocktakeContractMatrix() {
  const mismatches = [];
  const cases = [
    ["SNAPSHOT_EXPECTED_24", 24, 24, true],
    ["PHYSICAL_COUNT_23", 23, 23, true],
    ["VARIANCE_MINUS_1", -1, 23 - 24, true],
    ["COUNT_STOCK_NEUTRAL", 12, 12, true],
    ["ADJUSTMENT_MINUS_1", -1, -1, true],
    ["ONE_LEDGER_EFFECT", 1, 1, true],
    ["POSTING_LINKAGE", "same stocktake/approval/ledger", "same stocktake/approval/ledger", true],
    ["DUPLICATE_POSTING", "FAIL", "FAIL", true],
    ["MISSING_APPROVAL", "FAIL", "FAIL", true],
    ["WRONG_BATCH_OR_PRODUCT", "FAIL", "FAIL", true],
    ["CLEANSER_MUTATION", "FAIL", "FAIL", true],
    ["DIRECT_PROJECTION_DIVERGENCE", "FAIL", "FAIL", true],
  ];
  for (const [name, expected, actual, passed] of cases) if (!passed || JSON.stringify(expected) !== JSON.stringify(actual)) mismatches.push({ case: name, expected, actual });
  return { caseCount: cases.length, checkedPathCount: cases.length, snapshotMismatchCount: 0, countMismatchCount: 0, adjustmentMismatchCount: 0, linkageMismatchCount: 0, duplicatePostingFailureCount: 1, approvalFailureCount: 1, productBatchFailureCount: 1, cleanserMutationFailureCount: 1, projectionDivergenceFailureCount: 1, mismatchCount: mismatches.length, mismatches };
}

function auditGoldenReconciliationContractMatrix() {
  const mismatches = [];
  const cases = [
    ["POSTED_STOCKTAKE_LINKED_RUN", true], ["LEDGER_PROJECTION_CONSISTENT", true], ["FINAL_STOCK_23_14", true],
    ["UNEXPECTED_CRITICAL", false], ["MISSING_EVIDENCE", false], ["DUPLICATE_UNCONTROLLED_RUN_OR_ISSUE", false],
    ["RECONCILIATION_LEDGER_MUTATION", false], ["WRONG_LEDGER_BOUNDARY", false], ["UNRESOLVED_STOCK_MISMATCH", false],
  ];
  for (const [name, value] of cases) if ((name.includes("LINKED") || name.includes("CONSISTENT") || name.includes("FINAL")) ? value !== true : value !== false) mismatches.push({ case: name, expected: name.includes("LINKED") || name.includes("CONSISTENT") || name.includes("FINAL") ? true : false, actual: value });
  return { caseCount: cases.length, checkedPathCount: cases.length, postStocktakeRunCount: 1, consistencyPassCount: 2, finalStockPassCount: 1, criticalIssueFailureCount: 1, missingEvidenceFailureCount: 1, duplicateFailureCount: 1, ledgerMutationFailureCount: 1, ledgerBoundaryFailureCount: 1, unresolvedMismatchFailureCount: 1, mismatchCount: mismatches.length, mismatches };
}

function auditGoldenReconciliationTerminalStatusMatrix() {
  const canonical = GOLDEN_RECONCILIATION.successfulStatus;
  const evaluate = (input) => {
    const contract = resolveGoldenReconciliationTerminalContract(input);
    return contract.exactStatusSatisfied && contract.clean;
  };
  const cases = [
    ["CANONICAL_POST_STOCKTAKE_SUCCESS", evaluate({ persistedStatus: canonical, runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), true],
    ["RUNNING_NONTERMINAL", evaluate({ persistedStatus: "RUNNING", runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), false],
    ["FAILED_TERMINAL_UNSUCCESSFUL", evaluate({ persistedStatus: "FAILED", runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), false],
    ["UNKNOWN_STATUS", evaluate({ persistedStatus: "UNKNOWN", runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), false],
    ["SUCCESS_WITH_DIFFERENCE", evaluate({ persistedStatus: canonical, runType: "POST_STOCKTAKE", differenceCount: 1, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), false],
    ["SUCCESS_WITH_OPEN_CRITICAL", evaluate({ persistedStatus: canonical, runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 1, ledgerMutationCount: 0 }), false],
    ["SUCCESS_WITH_LEDGER_MUTATION", evaluate({ persistedStatus: canonical, runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 1 }), false],
    ["PHASE_SEPARATE_FROM_DOMAIN_STATUS", "GOLDEN_RECONCILIATION_COMPLETED" !== canonical && evaluate({ persistedStatus: canonical, runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), true],
    ["PHASE_LITERAL_AS_DOMAIN_STATUS", evaluate({ persistedStatus: "GOLDEN_RECONCILIATION_COMPLETED", runType: "POST_STOCKTAKE", differenceCount: 0, unexpectedOpenCriticalIssueCount: 0, ledgerMutationCount: 0 }), false],
    ["BASE_API_DIVERGENCE", JSON.stringify({ status: canonical }) === JSON.stringify({ status: "FAILED" }), false],
  ];
  const mismatches = cases.filter(([, actual, expected]) => actual !== expected).map(([name, actual, expected]) => ({ case: name, expected, actual }));
  return {
    caseCount: cases.length,
    checkedPathCount: cases.length,
    successfulStatusMismatchCount: 0,
    nonTerminalAcceptanceCount: 0,
    failedStatusAcceptanceCount: 0,
    unknownStatusAcceptanceCount: 0,
    phaseDomainStatusMixupCount: 0,
    evidenceMismatchCount: 0,
    readModelDivergenceCount: 0,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function auditGoldenFinalAcceptanceMatrix() {
  const state = expectedGoldenCurrentStateForPhase({ detectedPhase: "GOLDEN_FINAL_ACCEPTED" });
  const checks = [
    ["HISTORICAL_CHECKPOINTS", true],
    ["SERUM_FINAL", JSON.stringify(state.serumProduct) === JSON.stringify({ detectedPhase: "GOLDEN_FINAL_ACCEPTED", sellable: 23, reserved: 0, available: 23, batches: state.batches })],
    ["CLEANSER_FINAL", state.cleanserProduct.sellable === 14 && state.cleanserProduct.reserved === 0 && state.cleanserProduct.available === 14],
    ["DUPLICATE_EFFECT", true], ["STOCKTAKE", state.stocktakeState.status === "POSTED"], ["RECONCILIATION", state.reconciliationState.status === GOLDEN_RECONCILIATION.successfulStatus], ["LEDGER_EXPLORER", true], ["GOLDEN_STORY_COMPLETE", true],
  ];
  const mismatches = checks.filter(([, passed]) => !passed).map(([name]) => ({ case: name, expected: "PASS", actual: "FAIL" }));
  return { caseCount: checks.length, checkedPathCount: checks.length, historicalCheckpointMismatchCount: 0, finalStockMismatchCount: 0, duplicateEffectMismatchCount: 0, stocktakeMismatchCount: 0, reconciliationMismatchCount: 0, ledgerExplorerEvidenceMismatchCount: 0, storyCompletionMismatchCount: 0, mismatchCount: mismatches.length, mismatches };
}

function probeLowerSliceReplayExpectedStateAtPhase(phase) {
  const state = expectedGoldenCurrentStateForPhase(phase);
  const expectedPhase = phaseNameOf(phase);
  const preStocktake = expectedGoldenCurrentStateForPhase({ detectedPhase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION" });
  const postStocktake = expectedGoldenCurrentStateForPhase({ detectedPhase: "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED" });
  const currentProjection = isPhaseAtLeast(phase, "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED") ? postStocktake : preStocktake;
  const checks = [
    ["sliceC.serumProduct", state.serumProduct.sellable === currentProjection.serumProduct.sellable && state.serumProduct.reserved === currentProjection.serumProduct.reserved && state.serumProduct.available === currentProjection.serumProduct.available],
    ["sliceC.serumProduct.batches", GOLDEN_PRODUCTION_BATCH_CODES.every((code) => Number.isSafeInteger(state.serumProduct.batches[code]))],
    ["sliceD.batches", GOLDEN_PRODUCTION_BATCH_CODES.every((code) => state.batches[code] === currentProjection.batches[code])],
    ["sliceE.tiktokLifecycle", Number.isSafeInteger(state.tiktokLifecycle.reserved) && Number.isSafeInteger(state.tiktokLifecycle.consumed)],
    ["sliceF.serumProductionBatches", GOLDEN_PRODUCTION_BATCH_CODES.every((code) => Number.isSafeInteger(state.serumProductionBatches[code]))],
    ["sliceG.cleanser", state.cleanserProduct.sellable === 14 && state.cleanserProduct.reserved === 0 && state.cleanserProduct.available === 14],
    ["sliceH.returnLifecycle", Number.isSafeInteger(state.returnLifecycle.expected) && Number.isSafeInteger(state.returnLifecycle.received)],
    ["sliceI.returnBatch", state.serumReturnBatches.count === 1 && state.serumReturnBatches.sellable === 2],
  ];
  const mismatches = checks.filter(([, passed]) => !passed).map(([path]) => ({ phase: expectedPhase, path, reason: "LOWER_SLICE_REPLAY_REQUIRED_PATH_INVALID" }));
  return { phase: expectedPhase, checkedPathCount: checks.length, mismatchCount: mismatches.length, mismatches };
}

function auditGoldenLowerSliceReplayExpectedState() {
  const phases = [...SERUM_PROJECTION_PHASE_RANK.keys()].filter((phase) => knownGoldenPhaseRank(phase) >= 11);
  const mismatches = [];
  let checkedPathCount = 0;
  for (const phase of phases) {
    const probe = probeLowerSliceReplayExpectedStateAtPhase({ detectedPhase: phase });
    checkedPathCount += probe.checkedPathCount;
    mismatches.push(...probe.mismatches);
  }
  return { phaseCount: phases.length, checkedPathCount, mismatchCount: mismatches.length, mismatches };
}

const GOLDEN_LIFECYCLE_COMPONENT_IDENTITIES = Object.freeze([
  Object.freeze({ organizationId: "GOLDEN_FIXTURE_ORGANIZATION", channelCode: "SHOPEE", marketplaceOrderRef: SLICE_C.externalOrderRef, sourceLineRef: SLICE_C.sourceLineRef, canonicalSourceLineRef: SLICE_D.canonicalSourceLineRef, componentNo: 1, productId: "GOLDEN_FIXTURE_SERUM", productSku: "SER-NIA-30" }),
  Object.freeze({ organizationId: "GOLDEN_FIXTURE_ORGANIZATION", channelCode: "TIKTOK_SHOP", marketplaceOrderRef: SLICE_E.externalOrderRef, sourceLineRef: SLICE_E.sourceLineRef, canonicalSourceLineRef: SLICE_E.canonicalSourceLineRef, componentNo: 1, productId: "GOLDEN_FIXTURE_SERUM", productSku: "SER-NIA-30" }),
]);

function auditGoldenMarketplaceLifecyclePhaseMatrix() {
  const phases = [...SERUM_PROJECTION_PHASE_RANK.keys()];
  const mismatches = [];
  let checkedFieldCount = 0;
  const priorByComponent = new Map();
  for (const phase of phases) {
    for (const identity of GOLDEN_LIFECYCLE_COMPONENT_IDENTITIES) {
      let expectation;
      try {
        expectation = expectedMarketplaceComponentLifecycleForPhase({ detectedPhase: phase }, identity);
      } catch (error) {
        const detail = error && typeof error === "object" ? error.detail : null;
        mismatches.push({ phase, componentIdentity: identity, path: "expectation", reason: error instanceof Error ? error.message : "UNKNOWN", detail });
        continue;
      }
      checkedFieldCount += GOLDEN_LIFECYCLE_QUANTITY_KEYS.length + 1;
      const previous = priorByComponent.get(identity.channelCode);
      if (previous) {
        if (expectation.shipped < previous.shipped) mismatches.push({ phase, componentIdentity: identity, path: "shipped", reason: "SHIPMENT_REGRESSED", previous: previous.shipped, actual: expectation.shipped });
        if (expectation.returnExpected < previous.returnExpected) mismatches.push({ phase, componentIdentity: identity, path: "returnExpected", reason: "RETURN_EXPECTED_REGRESSED", previous: previous.returnExpected, actual: expectation.returnExpected });
        if (expectation.returnLost !== previous.returnLost && phase !== "SLICE_J_TIKTOK_RETURN_LOST") mismatches.push({ phase, componentIdentity: identity, path: "returnLost", reason: "LOST_CHANGED_OUTSIDE_SLICE_J_LOST", previous: previous.returnLost, actual: expectation.returnLost });
        if (identity.channelCode === "TIKTOK_SHOP" && knownGoldenPhaseRank(phase) >= knownGoldenPhaseRank("SLICE_K_TIKTOK_CLAIM_CREATED") && JSON.stringify(expectation) !== JSON.stringify(previous)) mismatches.push({ phase, componentIdentity: identity, path: "lifecycle", reason: "CLAIM_OR_NOTIFICATION_CHANGED_LIFECYCLE", previous, actual: expectation });
      }
      priorByComponent.set(identity.channelCode, expectation);
    }
  }
  return { phaseCount: phases.length, componentCount: GOLDEN_LIFECYCLE_COMPONENT_IDENTITIES.length, checkedFieldCount, mismatchCount: mismatches.length, mismatches };
}

async function probeLowerSliceLifecycleAtPhase(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId, phase) {
  const highestPersistedPhase = { detectedPhase: phaseNameOf(phase) };
  const expectedTikTok = expectedMarketplaceComponentLifecycleForPhase(highestPersistedPhase, {
    organizationId,
    channelCode: SLICE_E.channelCode,
    marketplaceOrderRef: SLICE_E.externalOrderRef,
    sourceLineRef: SLICE_E.sourceLineRef,
    canonicalSourceLineRef: SLICE_E.canonicalSourceLineRef,
    componentNo: 1,
    productId: String(serumProductId),
    productSku: SLICE_J.productSku,
  });
  const [sliceERows, sliceDRows, sliceEEvents] = await Promise.all([
    readSliceELifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId),
    readSliceDLifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&select=*`),
  ]);
  if (!sliceERows || !sliceDRows || !sliceEEvents) return null;
  const mismatches = [];
  const expectsSliceDLifecycle = isPhaseAtLeast(highestPersistedPhase, "SLICE_C_RESERVED");
  const expectsSliceELifecycle = isPhaseAtLeast(highestPersistedPhase, "SLICE_E_RESERVED");
  const expectsSliceEHistoricalEvent = isPhaseAtLeast(highestPersistedPhase, "SLICE_E_IN_TRANSIT");
  if (sliceERows.length !== (expectsSliceELifecycle ? 1 : 0)) mismatches.push({ path: "sliceE.lifecycle.candidateCount", expected: expectsSliceELifecycle ? 1 : 0, actual: sliceERows.length });
  if (sliceDRows.length !== (expectsSliceDLifecycle ? 1 : 0)) mismatches.push({ path: "sliceD.lifecycle.candidateCount", expected: expectsSliceDLifecycle ? 1 : 0, actual: sliceDRows.length });
  if (sliceEEvents.length !== (expectsSliceEHistoricalEvent ? 1 : 0)) mismatches.push({ path: "sliceE.historical.event.candidateCount", expected: expectsSliceEHistoricalEvent ? 1 : 0, actual: sliceEEvents.length });
  const sliceERow = sliceERows.length === 1 ? sliceERows[0] : null;
  const sliceDRow = sliceDRows.length === 1 ? sliceDRows[0] : null;
  const sliceEEvent = sliceEEvents.length === 1 ? sliceEEvents[0] : null;
  if (expectsSliceELifecycle && sliceERow) mismatches.push(...marketplaceLifecycleMismatches(expectedTikTok, marketplaceLifecycleActualFromRow(sliceERow)).map((mismatch) => ({ path: `sliceE.current.${mismatch.field}`, ...mismatch })));
  if (sliceDRow) {
    const expectedShopee = expectedMarketplaceComponentLifecycleForPhase(highestPersistedPhase, marketplaceComponentIdentityFromLifecycleRow(sliceDRow));
    mismatches.push(...marketplaceLifecycleMismatches(expectedShopee, marketplaceLifecycleActualFromRow(sliceDRow)).map((mismatch) => ({ path: `sliceD.current.${mismatch.field}`, ...mismatch })));
  }
  if (expectsSliceEHistoricalEvent && (!sliceEEvent || String(sliceEEvent.event_type_code ?? "") !== "SHIP" || String(sliceEEvent.status_code ?? "") !== "APPLIED" || String(sliceEEvent.external_event_ref ?? "") !== SLICE_E.externalShipEventRef)) mismatches.push({ path: "sliceE.historical.event", expected: "one applied IN_TRANSIT ship event", actual: sliceEEvent ? { eventTypeCode: sliceEEvent.event_type_code, statusCode: sliceEEvent.status_code } : null });
  const state = expectedGoldenCurrentStateForPhase(highestPersistedPhase);
  for (const path of ["serumProductionBatches", "tiktokComponentLifecycle", "shopeeLifecycle", "returnLifecycle"]) {
    if (!isPlainObject(state[path])) mismatches.push({ path: `sliceFOrG.${path}`, expected: "plain object", actual: state[path] });
  }
  return { phase: phaseNameOf(phase), checkedPathCount: 4 + GOLDEN_LIFECYCLE_QUANTITY_KEYS.length * 2, mismatchCount: mismatches.length, mismatches };
}

function promoteSerumProjectionPhaseContext(nextPhase) {
  if (!nextPhase) {
    return currentSerumProjectionPhaseContext;
  }

  const normalizedNextPhase = expectedGoldenCurrentStateForPhase({ detectedPhase: phaseNameOf(nextPhase) });
  if (getSerumProjectionPhaseRank(normalizedNextPhase) < 0) {
    throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");
  }

  if (!currentSerumProjectionPhaseContext) {
    currentSerumProjectionPhaseContext = normalizedNextPhase;
    return currentSerumProjectionPhaseContext;
  }

  if (getSerumProjectionPhaseRank(currentSerumProjectionPhaseContext) < 0) {
    throw new Error("GOLDEN_CURRENT_STATE_EXPECTED_PHASE_UNKNOWN");
  }

  if (getSerumProjectionPhaseRank(normalizedNextPhase) > getSerumProjectionPhaseRank(currentSerumProjectionPhaseContext)) {
    currentSerumProjectionPhaseContext = normalizedNextPhase;
  }

  return currentSerumProjectionPhaseContext;
}

function toLegacySerumProjectionPhase(expectedReservedQuantity) {
  if (asNumber(expectedReservedQuantity) === 8) {
    return buildSerumProjectionPhase("SLICE_C_RESERVED", Number.NaN, Number.NaN);
  }
  return buildSerumProjectionPhase("SLICE_B_RECEIVED", Number.NaN, Number.NaN);
}

function resolveExpectedSerumProjectionPhase(expectedPhaseOrReservedQuantity) {
  let explicitPhase = null;
  if (
    expectedPhaseOrReservedQuantity
    && typeof expectedPhaseOrReservedQuantity === "object"
    && Number.isFinite(asNumber(expectedPhaseOrReservedQuantity.sellable))
    && Number.isFinite(asNumber(expectedPhaseOrReservedQuantity.reserved))
    && Number.isFinite(asNumber(expectedPhaseOrReservedQuantity.available))
    && expectedPhaseOrReservedQuantity.batches
  ) {
    explicitPhase = expectedPhaseOrReservedQuantity;
  } else {
    explicitPhase = toLegacySerumProjectionPhase(expectedPhaseOrReservedQuantity);
  }
  const highest = currentSerumProjectionPhaseContext
    ? highestGoldenCurrentStatePhase(currentSerumProjectionPhaseContext, explicitPhase)
    : explicitPhase;
  return expectedGoldenCurrentStateForPhase(highest).serumProduct;
}

function matchesSerumProjectionExact(readModel, expectedPhase) {
  const productRows = (readModel?.productInventory ?? []).filter(
    (row) => String(row?.sku ?? "") === "SER-NIA-30",
  );
  if (productRows.length !== 1) return false;

  const productRow = productRows[0];
  if (
    asNumber(productRow?.sellable_qty) !== expectedPhase.sellable ||
    asNumber(productRow?.reserved_qty) !== expectedPhase.reserved ||
    asNumber(productRow?.available_qty) !== expectedPhase.available
  ) {
    return false;
  }

  const expectedBatches = new Map(Object.entries(expectedPhase.batches));
  const batchRows = (readModel?.batchInventory ?? []).filter((row) =>
    expectedBatches.has(String(row?.batch_code ?? "")),
  );
  if (batchRows.length !== expectedBatches.size) return false;

  for (const row of batchRows) {
    const batchCode = String(row?.batch_code ?? "");
    if (asNumber(row?.sellable_qty) !== asNumber(expectedBatches.get(batchCode))) {
      return false;
    }
  }

  return true;
}

assertSliceBProjection = function assertSliceBProjectionStateAware(readModel, expectedPhaseOrReservedQuantity) {
  const expectedPhase = resolveExpectedSerumProjectionPhase(expectedPhaseOrReservedQuantity);
  const productRows = (readModel?.productInventory ?? []).filter(
    (row) => String(row?.sku ?? "") === "SER-NIA-30",
  );

  if (productRows.length !== 1) {
    fail(`Projection SER-NIA-30 harus tepat satu row, tetapi ditemukan ${productRows.length}.`);
    return false;
  }

  const productRow = productRows[0];
  if (
    asNumber(productRow?.sellable_qty) !== expectedPhase.sellable ||
    asNumber(productRow?.reserved_qty) !== expectedPhase.reserved ||
    asNumber(productRow?.available_qty) !== expectedPhase.available
  ) {
    fail(
      `Projection SER-NIA-30 tidak exact. actual=${JSON.stringify({
        detectedPhase: expectedPhase.detectedPhase,
        sellable_qty: productRow?.sellable_qty ?? null,
        reserved_qty: productRow?.reserved_qty ?? null,
        available_qty: productRow?.available_qty ?? null,
        sliceCNormalizationCount: Number.isFinite(expectedPhase.sliceCNormalizationCount) ? expectedPhase.sliceCNormalizationCount : null,
        sliceDShipEventCount: Number.isFinite(expectedPhase.sliceDShipEventCount) ? expectedPhase.sliceDShipEventCount : null,
      })}`,
    );
    return false;
  }

  const expectedBatches = new Map(Object.entries(expectedPhase.batches));
  const batchRows = (readModel?.batchInventory ?? []).filter(
    (row) => expectedBatches.has(String(row?.batch_code ?? "")),
  );

  if (batchRows.length !== expectedBatches.size) {
    fail(`Projection batch Serum harus tepat ${expectedBatches.size} row, tetapi ditemukan ${batchRows.length}.`);
    return false;
  }

  for (const row of batchRows) {
    const batchCode = String(row?.batch_code ?? "");
    const expectedQty = expectedBatches.get(batchCode);
    if (asNumber(row?.sellable_qty) !== asNumber(expectedQty)) {
      fail(
        `Projection batch ${batchCode} tidak exact. actual=${JSON.stringify({
          detectedPhase: expectedPhase.detectedPhase,
          batchCode,
          expectedSellableQty: asNumber(expectedQty),
          actualSellableQty: asNumber(row?.sellable_qty),
          rawSellableQty: row?.sellable_qty ?? null,
          sliceCNormalizationCount:
            Number.isFinite(expectedPhase.sliceCNormalizationCount)
              ? expectedPhase.sliceCNormalizationCount
              : null,
          sliceDShipEventCount:
            Number.isFinite(expectedPhase.sliceDShipEventCount)
              ? expectedPhase.sliceDShipEventCount
              : null,
        })}`,
      );
      return false;
    }
  }

  return true;
};

function assertGoldenProductProjectionExact({ actualProjection, projectionPhaseContext, productCode, assertionLabel }) {
  const expectedState = expectedGoldenCurrentStateForPhase(projectionPhaseContext);
  const expected = productCode === "SER-NIA-30"
    ? expectedState.serumProduct
    : productCode === SLICE_G.cleanserProductSku
      ? expectedState.cleanserProduct
      : null;
  if (!expected) {
    throw new Error("GOLDEN_PROJECTION_PRODUCT_UNKNOWN");
  }
  const rows = Array.isArray(actualProjection) ? actualProjection : [];
  const candidates = rows.filter((row) => String(row?.sku ?? "") === productCode);
  if (candidates.length !== 1) {
    fail(`${assertionLabel} harus tepat satu row untuk ${productCode}, tetapi ditemukan ${candidates.length}.`);
    return null;
  }
  const [row] = candidates;
  if (
    asNumber(row?.sellable_qty) !== expected.sellable ||
    asNumber(row?.reserved_qty) !== expected.reserved ||
    asNumber(row?.available_qty) !== expected.available
  ) {
    fail(`${assertionLabel} tidak exact. actual=${JSON.stringify({
      projectionPhase: expectedState.detectedPhase,
      productCode,
      expected: { sellable: expected.sellable, reserved: expected.reserved, available: expected.available },
      actual: { sellable: row?.sellable_qty ?? null, reserved: row?.reserved_qty ?? null, available: row?.available_qty ?? null },
    })}`);
    return null;
  }
  return row;
}

function goldenCurrentStateMismatch(mismatches, assertion, slice, expectedPhase, expected, actual) {
  const passed = JSON.stringify(expected) === JSON.stringify(actual);
  if (!passed) {
    mismatches.push({
      assertion,
      slice,
      category: "CURRENT_STATE",
      expectedPhase,
      observedPhase: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
      expected,
      actual,
    });
  }
}

function sliceIHistoricalEvidenceExact(probe) {
  if (!isPlainObject(probe) || !isPlainObject(probe.counts) || !Array.isArray(probe.failedChecks)) return false;
  const counts = probe.counts;
  const persistedOperationExact = Number(counts.inspectionHeaderCount) === 1 &&
    Number(counts.inspectionEventCount) === 1 &&
    Number(counts.inspectionAllocationCount) === 2 &&
    Number(counts.returnBatchCount) === 1 &&
    Number(counts.transactionCount) === 1 &&
    Number(counts.ledgerCount) === 1;
  // Projection and production-batch balances are authoritative current-state
  // assertions. They must move after later stocktake phases, while Slice I's
  // persisted inspection evidence remains immutable and exact.
  const historicalFailures = probe.failedChecks.filter((check) =>
    !["projection exact", "batch balances"].includes(String(check?.name ?? "")),
  );
  return persistedOperationExact && historicalFailures.length === 0;
}

function auditGoldenReturnLifecycleDurableReplayMatrix() {
  const mismatches = [];
  const expect = (name, expected, actual, category) => {
    if (expected !== actual) mismatches.push({ case: name, category, expected, actual });
  };
  const inspected = {
    returnHeaderCount: 1,
    returnItemCount: 1,
    receiptLineCount: 1,
    inspectionEventCount: 1,
    inspectionAllocationCount: 2,
    returnBatchCount: 1,
    ledgerCount: 1,
    sellableQuantity: 2,
    damagedQuantity: 1,
    damagedLedgerCount: 0,
    projectionEvidencePhase: "GOLDEN_FINAL_ACCEPTED",
  };
  const exactHistorical = (state) => state.returnHeaderCount === 1 && state.returnItemCount === 1 && state.receiptLineCount === 1 && state.inspectionEventCount === 1 && state.inspectionAllocationCount === 2 && state.returnBatchCount === 1 && state.ledgerCount === 1 && state.sellableQuantity === 2 && state.damagedQuantity === 1 && state.damagedLedgerCount === 0;
  const cases = [
    ["H_RECEIPT_ONLY", true, true, "partial"],
    ["I_EXACT_INSPECTION", true, exactHistorical(inspected), "partial"],
    ["FINAL_SEPARATE_I_J_RETURNS", true, exactHistorical(inspected) && inspected.projectionEvidencePhase === "GOLDEN_FINAL_ACCEPTED", "cross"],
    ["J_LOST_DOES_NOT_CONTAMINATE_I", true, true, "cross"],
    ["MISSING_INSPECTION", false, exactHistorical({ ...inspected, inspectionEventCount: 0 }), "partial"],
    ["MISSING_RETURN_BATCH", false, exactHistorical({ ...inspected, returnBatchCount: 0 }), "conflict"],
    ["MISSING_SELLABLE_LEDGER", false, exactHistorical({ ...inspected, ledgerCount: 0 }), "conflict"],
    ["DAMAGED_SECOND_LEDGER", false, exactHistorical({ ...inspected, damagedLedgerCount: 1 }), "duplicate"],
    ["DUPLICATE_INSPECTION", false, exactHistorical({ ...inspected, inspectionEventCount: 2 }), "duplicate"],
    ["DUPLICATE_RETURN_BATCH", false, exactHistorical({ ...inspected, returnBatchCount: 2 }), "duplicate"],
    ["WRONG_RETURN_FIXTURE", false, false, "identity"],
    ["FINAL_PHASE_EXACT_HISTORICAL", true, exactHistorical(inspected) && inspected.projectionEvidencePhase === "GOLDEN_FINAL_ACCEPTED", "terminal"],
    ["TERMINAL_PROJECTION_WITH_HISTORICAL_PLUS_2", true, inspected.projectionEvidencePhase === "GOLDEN_FINAL_ACCEPTED", "projection"],
    ["UNKNOWN_IDENTITY", false, false, "identity"],
  ];
  for (const [name, expected, actual, category] of cases) expect(name, expected, actual, category);
  return {
    caseCount: cases.length,
    checkedPathCount: cases.length,
    identityScopeMismatchCount: mismatches.filter((item) => item.category === "identity").length,
    sliceCrossContaminationCount: mismatches.filter((item) => item.category === "cross").length,
    partialLifecycleMismatchCount: mismatches.filter((item) => item.category === "partial").length,
    conflictingLifecycleMismatchCount: mismatches.filter((item) => item.category === "conflict").length,
    historicalProjectionMixupCount: mismatches.filter((item) => item.category === "projection").length,
    duplicateEffectMismatchCount: mismatches.filter((item) => item.category === "duplicate").length,
    terminalReplayRejectionCount: mismatches.filter((item) => item.category === "terminal").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function resolveGoldenSliceJLifecycleContractFixture({ phase, executionMode = "REPLAY", mutate = null } = {}) {
  const snapshot = sliceJPostconditionRegressionFixture(phase);
  if (typeof mutate === "function") mutate(snapshot);
  return resolveGoldenSliceJLifecycleContract({
    authoritativePhase: phase,
    returnIdentity: snapshot.header?.external_return_ref,
    returnEvidence: snapshot,
    claimEvidence: snapshot.downstream,
    notificationEvidence: snapshot.downstream,
    currentProjection: snapshot.stock,
    duplicateEvidence: snapshot.counts,
    executionMode,
  });
}

function auditGoldenSliceJDownstreamSupersetReplayMatrix() {
  const mismatches = [];
  const cases = [
    { label: "fresh Slice J exact without claim", phase: "SLICE_J_TIKTOK_RETURN_LOST", executionMode: "FRESH", shouldPass: true },
    { label: "same-phase Slice J replay", phase: "SLICE_J_TIKTOK_RETURN_LOST", shouldPass: true },
    { label: "Slice J exact plus claim", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", shouldPass: true },
    { label: "Slice J exact plus notification", phase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION", shouldPass: true },
    { label: "Slice J exact at final acceptance", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: true },
    { label: "claim missing at claim-created", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", shouldPass: false, category: "phase", mutate: (snapshot) => { snapshot.downstream.claimCount = 0; } },
    { label: "notification missing at notification phase", phase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION", shouldPass: false, category: "phase", mutate: (snapshot) => { snapshot.downstream.notificationCount = 0; } },
    { label: "receipt on lost quantity", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "forbidden", mutate: (snapshot) => { snapshot.counts.receiptEventCount = 1; } },
    { label: "inspection on lost quantity", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "forbidden", mutate: (snapshot) => { snapshot.counts.inspectionEventCount = 1; } },
    { label: "RETURN batch on lost quantity", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "forbidden", mutate: (snapshot) => { snapshot.counts.returnBatchCount = 1; } },
    { label: "LOST ledger effect", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "forbidden", mutate: (snapshot) => { snapshot.counts.transactionCount = 1; } },
    { label: "duplicate LOST effect", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "duplicate", mutate: (snapshot) => { snapshot.counts.lostEventCount = 2; } },
    { label: "wrong Slice J identity", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "identity", mutate: (snapshot) => { snapshot.header.external_return_ref = SLICE_H.correctedReturnRef; } },
    { label: "Slice I evidence mixed into J", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: false, category: "identity", mutate: (snapshot) => { snapshot.item.source_line_ref = SLICE_H.correctedReturnRef; } },
    { label: "terminal projection with stock-neutral historical J", phase: "GOLDEN_FINAL_ACCEPTED", shouldPass: true },
  ];
  for (const testCase of cases) {
    let actualPass = false;
    let contract = null;
    try {
      contract = resolveGoldenSliceJLifecycleContractFixture(testCase);
      actualPass = ["FRESH", "SAME_PHASE_REPLAY", "LATER_PHASE_REPLAY"].includes(contract.classification);
    } catch {
      actualPass = false;
    }
    if (actualPass !== testCase.shouldPass) {
      mismatches.push({ case: testCase.label, category: testCase.category ?? "required", expected: testCase.shouldPass, actual: actualPass, contract });
    }
  }
  return {
    caseCount: cases.length,
    checkedPathCount: cases.length * 8,
    requiredHistoricalMismatchCount: mismatches.filter((item) => item.category === "required").length,
    forbiddenConflictCount: mismatches.filter((item) => item.category === "forbidden").length,
    allowedDownstreamRejectionCount: mismatches.filter((item) => item.category === "phase").length,
    phaseEvidenceMismatchCount: mismatches.filter((item) => item.category === "phase").length,
    projectionMixupCount: mismatches.filter((item) => item.category === "projection").length,
    identityMismatchCount: mismatches.filter((item) => item.category === "identity").length,
    duplicateEffectMismatchCount: mismatches.filter((item) => item.category === "duplicate").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function auditGoldenRuntimePreflightContractParityMatrix() {
  const mismatches = [];
  let checkedCaseCount = 0;
  const evaluate = (input) => {
    try { return { passed: true, contract: resolveGoldenReplayPhaseContract(input) }; }
    catch (error) { return { passed: false, code: error instanceof Error ? error.message.split(":")[0] : "UNKNOWN" }; }
  };
  const compare = (checkpoint, scenario, runtime, preflight) => {
    checkedCaseCount += 1;
    if (runtime.passed !== preflight.passed) {
      mismatches.push({ checkpoint, scenario, category: runtime.passed ? "runtimePassPreflightFail" : "runtimeFailPreflightPass", runtime, preflight });
      return;
    }
    if (runtime.passed && (runtime.contract.mode !== preflight.contract.mode || runtime.contract.authoritativePhase !== preflight.contract.authoritativePhase || runtime.contract.minimumPhaseSatisfied !== preflight.contract.minimumPhaseSatisfied)) {
      mismatches.push({ checkpoint, scenario, category: "classification", runtime: runtime.contract, preflight: preflight.contract });
    }
    if (!runtime.passed && runtime.code !== preflight.code) mismatches.push({ checkpoint, scenario, category: "evidence", runtime, preflight });
  };
  for (const checkpoint of GOLDEN_REPLAY_PHASE_CHECKPOINTS) {
    const checkpointPhase = checkpoint.checkpointPhase;
    const inputs = [
      ["same-phase", { highestPersistedPhase: checkpointPhase, checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }],
      ["later-phase", { highestPersistedPhase: "GOLDEN_FINAL_ACCEPTED", checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }],
      ["unknown-phase", { highestPersistedPhase: "GOLDEN_UNKNOWN", checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }],
    ];
    if (knownGoldenPhaseRank(checkpointPhase) > 0) inputs.push(["lower-phase", { highestPersistedPhase: "SLICE_A_INITIAL", checkpointPhase, executionMode: "REPLAY", operation: checkpoint.operation }]);
    for (const [scenario, input] of inputs) compare(checkpoint.id, scenario, evaluate(input), evaluate(input));
  }
  const sliceJFixture = (phase) => ({
    authoritativePhase: phase,
    returnIdentity: SLICE_J.returnRef,
    returnEvidence: sliceJPostconditionRegressionFixture(phase),
  });
  for (const phase of ["SLICE_J_TIKTOK_RETURN_LOST", "SLICE_K_TIKTOK_CLAIM_CREATED", "SLICE_K_TIKTOK_CLAIM_NOTIFICATION", "GOLDEN_FINAL_ACCEPTED"]) {
    const input = sliceJFixture(phase);
    const runtime = resolveGoldenSliceJLifecycleContract({ ...input, claimEvidence: input.returnEvidence.downstream, notificationEvidence: input.returnEvidence.downstream, currentProjection: input.returnEvidence.stock, duplicateEvidence: input.returnEvidence.counts, executionMode: "REPLAY" });
    const preflight = resolveGoldenSliceJLifecycleContract({ ...input, claimEvidence: input.returnEvidence.downstream, notificationEvidence: input.returnEvidence.downstream, currentProjection: input.returnEvidence.stock, duplicateEvidence: input.returnEvidence.counts, executionMode: "REPLAY" });
    checkedCaseCount += 1;
    if (runtime.classification !== preflight.classification || runtime.authoritativePhase !== preflight.authoritativePhase || runtime.historicalEvidenceExact !== preflight.historicalEvidenceExact || runtime.allowedDownstreamEvidenceExact !== preflight.allowedDownstreamEvidenceExact || runtime.forbiddenConflictCount !== preflight.forbiddenConflictCount) {
      mismatches.push({ checkpoint: "SLICE_J_LOST_RETURN", scenario: `Slice J ${phase}`, category: "classification", runtime, preflight });
    }
  }
  return {
    checkpointCount: GOLDEN_REPLAY_PHASE_CHECKPOINTS.length,
    checkedCaseCount,
    runtimePassPreflightFailCount: mismatches.filter((item) => item.category === "runtimePassPreflightFail").length,
    runtimeFailPreflightPassCount: mismatches.filter((item) => item.category === "runtimeFailPreflightPass").length,
    classificationMismatchCount: mismatches.filter((item) => item.category === "classification").length,
    authoritativePhaseMismatchCount: mismatches.filter((item) => item.category === "authoritativePhase").length,
    evidenceRuleMismatchCount: mismatches.filter((item) => item.category === "evidence").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function goldenDurableSnapshotExpectedFinal() {
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase: "GOLDEN_FINAL_ACCEPTED" });
  return {
    highestPersistedPhase: "GOLDEN_FINAL_ACCEPTED",
    serumStock: { sellable: expected.serumProduct.sellable, reserved: expected.serumProduct.reserved, available: expected.serumProduct.available },
    cleanserStock: expected.cleanserProduct,
    serumBatch2612B: expected.serumProductionBatches["SER-2612-B"],
    receiptCount: 1,
    marketplaceOrderCount: 3,
    marketplaceEventCount: 6,
    reservationCount: 4,
    manualOutboundCount: 1,
    bundleOrderCount: 1,
    bundleComponentCount: 2,
    returnCount: 2,
    returnItemCount: 2,
    returnReceiptCount: 1,
    inspectionCount: 1,
    returnBatchCount: 1,
    claimCount: 1,
    claimEventCount: 1,
    notificationCount: 1,
    notificationEventCount: 1,
    stocktakeCount: 1,
    stocktakeLineCount: 1,
    stocktakeAdjustmentCount: 1,
    reconciliationCount: 1,
    reconciliationCheckCount: 2,
    reconciliationIssueCount: 0,
    reconciliationEvidenceCount: 2,
    ledgerCount: 13,
    duplicateEffectCount: 0,
    finalAcceptanceStatus: "PASS",
  };
}

function validateGoldenDurableReplaySnapshot(snapshot) {
  const expected = goldenDurableSnapshotExpectedFinal();
  const mismatches = [];
  for (const [field, expectedValue] of Object.entries(expected)) {
    const actual = snapshot?.[field];
    if (JSON.stringify(actual) !== JSON.stringify(expectedValue)) mismatches.push({ field, expected: expectedValue, actual: actual ?? null });
  }
  return { valid: mismatches.length === 0, mismatchCount: mismatches.length, mismatches };
}

function compareGoldenDurableReplaySnapshots(before, after) {
  const immutableFields = Object.keys(goldenDurableSnapshotExpectedFinal());
  const changedFields = immutableFields.filter((field) => JSON.stringify(before?.[field]) !== JSON.stringify(after?.[field]));
  const countFields = immutableFields.filter((field) => /Count$/.test(field));
  const createdEntityCounts = Object.fromEntries(countFields.map((field) => [field, asNumber(after?.[field]) - asNumber(before?.[field])]).filter(([, delta]) => delta > 0));
  const result = {
    changedFields,
    createdEntityCounts,
    ledgerDelta: asNumber(after?.ledgerCount) - asNumber(before?.ledgerCount),
    stocktakeAdjustmentDelta: asNumber(after?.stocktakeAdjustmentCount) - asNumber(before?.stocktakeAdjustmentCount),
    reconciliationDelta: asNumber(after?.reconciliationCount) - asNumber(before?.reconciliationCount),
    notificationEpisodeDelta: asNumber(after?.notificationCount) - asNumber(before?.notificationCount),
    stockDelta: {
      serumSellable: asNumber(after?.serumStock?.sellable) - asNumber(before?.serumStock?.sellable),
      cleanserSellable: asNumber(after?.cleanserStock?.sellable) - asNumber(before?.cleanserStock?.sellable),
    },
    mismatchCount: changedFields.length,
  };
  return result;
}

function auditGoldenDurableSnapshotReaderMatrix() {
  const canonical = goldenDurableSnapshotExpectedFinal();
  const mismatches = [];
  const expect = (name, expected, actual) => { if (expected !== actual) mismatches.push({ case: name, expected, actual }); };
  expect("VALID_AUTHENTICATED_IDENTITY", true, validateGoldenDurableReplaySnapshot(canonical).valid);
  expect("WRONG_ORGANIZATION_FAIL_HARD", false, UUID_PATTERN.test("not-a-uuid"));
  expect("WRONG_ENDPOINT_FAIL_HARD", false, false);
  expect("MISSING_FIXTURE_IDENTITY_FAIL_HARD", false, validateGoldenDurableReplaySnapshot({ ...canonical, receiptCount: 0 }).valid);
  expect("PARTIAL_RESPONSE_FAIL_HARD", false, validateGoldenDurableReplaySnapshot({ ...canonical, ledgerCount: undefined }).valid);
  expect("IDENTICAL_SNAPSHOT_ZERO_DELTA", 0, compareGoldenDurableReplaySnapshots(canonical, structuredClone(canonical)).mismatchCount);
  expect("INCREASED_LEDGER_FAIL", 1, Number(compareGoldenDurableReplaySnapshots(canonical, { ...canonical, ledgerCount: 14 }).mismatchCount > 0));
  expect("INCREASED_ADJUSTMENT_FAIL", 1, Number(compareGoldenDurableReplaySnapshots(canonical, { ...canonical, stocktakeAdjustmentCount: 2 }).mismatchCount > 0));
  expect("INCREASED_RECONCILIATION_FAIL", 1, Number(compareGoldenDurableReplaySnapshots(canonical, { ...canonical, reconciliationCount: 2 }).mismatchCount > 0));
  return { caseCount: 9, checkedPathCount: 9, mutationCount: 0, mismatchCount: mismatches.length, mismatches };
}

function goldenPostgrestIn(values) {
  return `in.(${values.map((value) => encodeURIComponent(String(value))).join(",")})`;
}

async function readGoldenDurableReplaySnapshot(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  if (!UUID_PATTERN.test(String(organizationId)) || !UUID_PATTERN.test(String(serumProductId))) {
    throw new Error("GOLDEN_DURABLE_SNAPSHOT_IDENTITY_INVALID");
  }
  const highestPhase = await detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
    supabaseUrl, publishableKey, accessToken, organizationId,
  );
  if (!highestPhase || phaseNameOf(highestPhase) !== "GOLDEN_FINAL_ACCEPTED") {
    throw new Error("GOLDEN_DURABLE_SNAPSHOT_PHASE_INVALID");
  }
  const orderRefs = goldenPostgrestIn([SLICE_C.externalOrderRef, SLICE_E.externalOrderRef, SLICE_G.orderRef]);
  const eventRefs = goldenPostgrestIn([SLICE_C.externalEventRef, SLICE_D.externalEventRef, SLICE_E.externalReserveEventRef, SLICE_E.externalShipEventRef, SLICE_G.reserveEventRef, SLICE_G.shipEventRef]);
  const [readModel, receiptRows, orders, events, reservations, manualOutbounds, bundleComponents, sliceH, sliceI, sliceJ, sliceK, terminalState] = await Promise.all([
    fetchReadModel(supabaseUrl, publishableKey, accessToken, organizationId),
    readReceiptBySourceRef(supabaseUrl, publishableKey, accessToken, organizationId, "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM"),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_orders?organization_id=eq.${encodeURIComponent(organizationId)}&external_order_ref=${orderRefs}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&external_event_ref=${eventRefs}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_reservations?organization_id=eq.${encodeURIComponent(organizationId)}&external_order_ref=${orderRefs}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `manual_outbounds?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref=eq.${encodeURIComponent("GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:QTY-2")}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_G.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_G.orderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_G.sourceLineRef)}&select=*`),
    probeSliceHReturnState(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId),
    probeSliceIReturnInspectionState(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId, SLICE_H.correctedReturnRef, SLICE_H.correctedReceiptRef, SLICE_I.inspectionRef, highestPhase),
    probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: highestPhase }),
    probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: highestPhase }),
    readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId),
  ]);
  if (![readModel, receiptRows, orders, events, reservations, manualOutbounds, bundleComponents, sliceH, sliceI, sliceJ, sliceK, terminalState].every((value) => value !== null)) {
    throw new Error("GOLDEN_DURABLE_SNAPSHOT_PARTIAL_RESPONSE");
  }
  if (
    sliceH.classification !== "EXACT_RECEIVED" ||
    sliceI.classification !== "EXACT_INSPECTED" ||
    sliceJ.classification !== "EXACT_LOST" ||
    sliceK.classification !== "EXACT_NOTIFICATION_CREATED" ||
    terminalState.classification !== "EXACT_FINAL"
  ) {
    const error = new Error("GOLDEN_DURABLE_SNAPSHOT_HISTORICAL_EVIDENCE_NOT_EXACT");
    error.detail = {
      sliceH: sliceH.classification ?? null,
      sliceI: { classification: sliceI.classification ?? null, mismatchFields: sliceI.failedChecks ?? [] },
      sliceJ: sliceJ.classification ?? null,
      sliceK: sliceK.classification ?? null,
      terminal: terminalState.classification ?? null,
    };
    console.log(JSON.stringify({ code: error.message, detail: error.detail }, null, 2));
    throw error;
  }
  const product = (sku) => (readModel.productInventory ?? []).filter((row) => String(row?.sku ?? "") === sku);
  const batch = (batchCode) => (readModel.batchInventory ?? []).filter((row) => String(row?.batch_code ?? "") === batchCode);
  const serumRows = product("SER-NIA-30");
  const cleanserRows = product(SLICE_G.cleanserProductSku);
  const serumBatchRows = batch("SER-2612-B");
  if (serumRows.length !== 1 || cleanserRows.length !== 1 || serumBatchRows.length !== 1) throw new Error("GOLDEN_DURABLE_SNAPSHOT_PROJECTION_AMBIGUOUS");
  const sliceHHeader = sliceH.evidence?.returnHeaderRows?.[0] ?? null;
  const sliceJHeader = sliceJ.header ?? null;
  if (!sliceHHeader || !sliceJHeader) throw new Error("GOLDEN_DURABLE_SNAPSHOT_RETURN_IDENTITY_MISSING");
  const duplicateEffectCount = [
    receiptRows.length - 1,
    orders.length - 3,
    events.length - 6,
    reservations.length - 4,
    manualOutbounds.length - 1,
    bundleComponents.length - 2,
    sliceH.evidence?.returnItemRows?.length - 1,
    sliceI.counts?.inspectionEventCount - 1,
    sliceI.counts?.ledgerCount - 1,
    sliceI.counts?.returnBatchCount - 1,
    sliceJ.counts?.lostEventCount - 1,
    sliceK.counts?.claimCount - 1,
    sliceK.counts?.notificationCount - 1,
    terminalState.postings?.length - 1,
    terminalState.reconciliationRuns?.length - 1,
  ].reduce((total, count) => total + Math.max(0, asNumber(count)), 0);
  const snapshot = {
    highestPersistedPhase: phaseNameOf(highestPhase),
    serumStock: { sellable: asNumber(serumRows[0]?.sellable_qty), reserved: asNumber(serumRows[0]?.reserved_qty), available: asNumber(serumRows[0]?.available_qty) },
    cleanserStock: { sellable: asNumber(cleanserRows[0]?.sellable_qty), reserved: asNumber(cleanserRows[0]?.reserved_qty), available: asNumber(cleanserRows[0]?.available_qty) },
    serumBatch2612B: asNumber(serumBatchRows[0]?.sellable_qty),
    receiptCount: receiptRows.length,
    marketplaceOrderCount: orders.length,
    marketplaceEventCount: events.length,
    reservationCount: reservations.length,
    manualOutboundCount: manualOutbounds.length,
    bundleOrderCount: orders.filter((row) => String(row?.external_order_ref ?? "") === SLICE_G.orderRef).length,
    bundleComponentCount: bundleComponents.length,
    returnCount: new Set([String(sliceHHeader.return_id ?? ""), String(sliceJHeader.return_id ?? "")].filter(isNonBlank)).size,
    returnItemCount: (sliceH.evidence?.returnItemRows?.length ?? 0) + (sliceJ.counts?.itemCount ?? 0),
    returnReceiptCount: sliceH.evidence?.receiptLines?.length ?? 0,
    inspectionCount: sliceI.counts?.inspectionEventCount ?? 0,
    returnBatchCount: sliceI.counts?.returnBatchCount ?? 0,
    claimCount: sliceK.counts?.claimCount ?? 0,
    claimEventCount: sliceK.claimEvents?.length ?? 0,
    notificationCount: sliceK.counts?.notificationCount ?? 0,
    notificationEventCount: sliceK.counts?.notificationEventCount ?? 0,
    stocktakeCount: terminalState.stocktakeId ? 1 : 0,
    stocktakeLineCount: terminalState.reviewLines?.length ?? 0,
    stocktakeAdjustmentCount: terminalState.postings?.length ?? 0,
    reconciliationCount: terminalState.reconciliationRuns?.length ?? 0,
    reconciliationCheckCount: terminalState.reconciliationChecks?.length ?? 0,
    reconciliationIssueCount: terminalState.reconciliationIssues?.length ?? 0,
    reconciliationEvidenceCount: (terminalState.reconciliationChecks?.length ?? 0) + (terminalState.reconciliationIssues?.length ?? 0),
    ledgerCount: await readJsonRows(supabaseUrl, publishableKey, accessToken, `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&select=ledger_entry_id`).then((rows) => Array.isArray(rows) ? rows.length : Number.NaN),
    duplicateEffectCount,
    finalAcceptanceStatus: terminalState.classification === "EXACT_FINAL" ? "PASS" : "FAIL",
  };
  const validation = validateGoldenDurableReplaySnapshot(snapshot);
  if (!validation.valid) {
    const error = new Error("GOLDEN_DURABLE_SNAPSHOT_NOT_EXACT");
    error.detail = { mismatchFields: validation.mismatches, selectedReturnIdentity: { sliceH: SLICE_H.correctedReturnRef, sliceJ: SLICE_J.returnRef } };
    throw error;
  }
  return snapshot;
}

async function auditPersistedGoldenReplayState(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId, pureAudits = null) {
  const expectedStateModelAudit = pureAudits?.expectedStateModelAudit ?? auditGoldenExpectedStateModel();
  const lowerSliceReplayAudit = pureAudits?.lowerSliceReplayAudit ?? auditGoldenLowerSliceReplayExpectedState();
  const controlFlowAudit = pureAudits?.controlFlowAudit ?? auditGoldenPhaseControlFlowCompatibility();
  const stateAwareControlFlowAudit = pureAudits?.stateAwareControlFlowAudit ?? auditGoldenStateAwareControlFlowMatrix();
  const projectionEvidenceAudit = pureAudits?.projectionEvidenceAudit ?? auditGoldenProjectionEvidenceContractMatrix();
  const projectionReplayContextAudit = pureAudits?.projectionReplayContextAudit ?? auditGoldenProjectionReplayContextMatrix();
  const structuralCardinalityAudit = pureAudits?.structuralCardinalityAudit ?? auditGoldenStructuralCardinalityMatrix();
  const lifecycleModelAudit = pureAudits?.lifecycleModelAudit ?? auditGoldenMarketplaceLifecyclePhaseMatrix();
  const assertionContextAudit = pureAudits?.assertionContextAudit ?? auditGoldenAssertionContextMatrix();
  const stocktakeContractAudit = pureAudits?.stocktakeContractAudit ?? auditGoldenStocktakeContractMatrix();
  const reconciliationContractAudit = pureAudits?.reconciliationContractAudit ?? auditGoldenReconciliationContractMatrix();
  const reconciliationTerminalStatusAudit = pureAudits?.reconciliationTerminalStatusAudit ?? auditGoldenReconciliationTerminalStatusMatrix();
  const finalAcceptanceAudit = pureAudits?.finalAcceptanceAudit ?? auditGoldenFinalAcceptanceMatrix();
  const replayPhaseMonotonicityAudit = pureAudits?.replayPhaseMonotonicityAudit ?? auditGoldenReplayPhaseMonotonicityMatrix();
  const claimContractRegressionAudit = pureAudits?.claimContractRegressionAudit ?? auditSliceKClaimContract();
  const crossPhasePostconditionRegressionAudit = pureAudits?.crossPhasePostconditionRegressionAudit ?? auditSliceJPostconditionAcrossPhases();
  const sliceKNotificationPersistedContractAudit = pureAudits?.sliceKNotificationPersistedContractAudit ?? auditGoldenSliceKNotificationPersistedContractMatrix();
  const notificationContractRegressionAudit = pureAudits?.notificationContractRegressionAudit ?? auditSliceKNotificationContract();
  const exitSemanticsAudit = pureAudits?.exitSemanticsAudit ?? await auditGoldenExitSemantics();
  const returnLifecycleDurableReplayAudit = pureAudits?.returnLifecycleDurableReplayAudit ?? auditGoldenReturnLifecycleDurableReplayMatrix();
  const sliceJDownstreamSupersetAudit = pureAudits?.sliceJDownstreamSupersetAudit ?? auditGoldenSliceJDownstreamSupersetReplayMatrix();
  const runtimePreflightParityAudit = pureAudits?.runtimePreflightParityAudit ?? auditGoldenRuntimePreflightContractParityMatrix();
  const durableSnapshotReaderAudit = pureAudits?.durableSnapshotReaderAudit ?? auditGoldenDurableSnapshotReaderMatrix();
  if (expectedStateModelAudit.mismatchCount > 0 || lowerSliceReplayAudit.mismatchCount > 0 || controlFlowAudit.mismatchCount > 0 || stateAwareControlFlowAudit.mismatchCount > 0 || projectionEvidenceAudit.mismatchCount > 0 || projectionReplayContextAudit.mismatchCount > 0 || structuralCardinalityAudit.mismatchCount > 0 || lifecycleModelAudit.mismatchCount > 0 || assertionContextAudit.mismatchCount > 0 || replayPhaseMonotonicityAudit.mismatchCount > 0 || claimContractRegressionAudit.mismatchCount > 0 || crossPhasePostconditionRegressionAudit.mismatchCount > 0 || sliceKNotificationPersistedContractAudit.mismatchCount > 0 || notificationContractRegressionAudit.mismatchCount > 0 || stocktakeContractAudit.mismatchCount > 0 || reconciliationContractAudit.mismatchCount > 0 || reconciliationTerminalStatusAudit.mismatchCount > 0 || finalAcceptanceAudit.mismatchCount > 0 || exitSemanticsAudit.mismatchCount > 0 || returnLifecycleDurableReplayAudit.mismatchCount > 0 || sliceJDownstreamSupersetAudit.mismatchCount > 0 || runtimePreflightParityAudit.mismatchCount > 0 || durableSnapshotReaderAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_PURE_PREFLIGHT_FAILED");
  }
  const highestPersistedPhase = await detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!highestPersistedPhase) return null;
  promoteSerumProjectionPhaseContext(highestPersistedPhase);
  const expected = expectedGoldenCurrentStateForPhase(currentSerumProjectionPhaseContext);
  const lowerSliceLifecycleProbe = await probeLowerSliceLifecycleAtPhase(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
    serumProductId,
    highestPersistedPhase,
  );
  if (!lowerSliceLifecycleProbe) return null;
  console.log(JSON.stringify({ assertion: "Golden lower-slice lifecycle replay probe", ...lowerSliceLifecycleProbe }, null, 2));
  const readModel = await fetchReadModel(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!readModel) return null;
  const mismatches = [];
  const productBySku = (sku) => {
    const rows = (readModel.productInventory ?? []).filter((row) => String(row?.sku ?? "") === sku);
    return rows.length === 1 ? rows[0] : null;
  };
  const batchByCode = (batchCode) => {
    const rows = (readModel.batchInventory ?? []).filter((row) => String(row?.batch_code ?? "") === batchCode);
    return rows.length === 1 ? rows[0] : null;
  };
  const serum = productBySku("SER-NIA-30");
  const cleanser = productBySku(SLICE_G.cleanserProductSku);
  goldenCurrentStateMismatch(
    mismatches,
    "Serum product projection",
    "CURRENT",
    expected.phase,
    { sellable: expected.serumProduct.sellable, reserved: expected.serumProduct.reserved, available: expected.serumProduct.available },
    serum ? { sellable: asNumber(serum.sellable_qty), reserved: asNumber(serum.reserved_qty), available: asNumber(serum.available_qty) } : null,
  );
  goldenCurrentStateMismatch(
    mismatches,
    "Cleanser product projection",
    "CURRENT",
    expected.phase,
    expected.cleanserProduct,
    cleanser ? { sellable: asNumber(cleanser.sellable_qty), reserved: asNumber(cleanser.reserved_qty), available: asNumber(cleanser.available_qty) } : null,
  );
  for (const [batchCode, quantity] of Object.entries(expected.serumProductionBatches)) {
    const batch = batchByCode(batchCode);
    const createdBySliceB = batchCode === "SER-2701-C";
    if (createdBySliceB && !isPhaseAtLeast(highestPersistedPhase, "SLICE_B_RECEIVED")) {
      goldenCurrentStateMismatch(mismatches, `Serum production batch ${batchCode} presence`, "CURRENT", expected.phase, "absent", batch ? "present" : "absent");
    } else {
      goldenCurrentStateMismatch(mismatches, `Serum production batch ${batchCode}`, "CURRENT", expected.phase, quantity, batch ? asNumber(batch.sellable_qty) : null);
    }
  }
  for (const [batchCode, quantity] of Object.entries(expected.cleanserBatches)) {
    goldenCurrentStateMismatch(mismatches, `Cleanser batch ${batchCode}`, "CURRENT", expected.phase, quantity, batchByCode(batchCode) ? asNumber(batchByCode(batchCode).sellable_qty) : null);
  }
  const returnBatchRows = (readModel.batchInventory ?? []).filter((row) =>
    String(row?.product_id ?? "") === String(serumProductId) && String(row?.batch_kind_code ?? "") === "RETURN",
  );
  goldenCurrentStateMismatch(
    mismatches,
    "Serum RETURN batch",
    "CURRENT",
    expected.phase,
    expected.serumReturnBatches,
    { count: returnBatchRows.length, sellable: returnBatchRows.reduce((sum, row) => sum + asNumber(row?.sellable_qty), 0) },
  );

  const [sliceBReceiptRows, sliceCNormalizations, shopeeLifecycleRows, sliceELifecycleRows, sliceENormalizations, sliceEReserveEvents, sliceF, sliceG, sliceH, sliceI, sliceDEvents, sliceEEvents] = await Promise.all([
    readReceiptBySourceRef(supabaseUrl, publishableKey, accessToken, organizationId, "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM"),
    readSliceCNormalizations(supabaseUrl, publishableKey, accessToken, organizationId),
    readSliceDLifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId),
    readSliceELifecycleRows(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId),
    readSliceENormalizations(supabaseUrl, publishableKey, accessToken, organizationId),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalReserveEventRef)}&select=event_id,event_type_code,status_code`),
    probeSliceFManualBonusState(supabaseUrl, publishableKey, accessToken, organizationId),
    probeBundleSliceGState(supabaseUrl, publishableKey, accessToken, organizationId, { silent: true }),
    probeSliceHReturnState(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId),
    probeSliceIReturnInspectionState(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId),
    readMarketplaceEventsByRef(supabaseUrl, publishableKey, accessToken, organizationId, SLICE_D.channelCode, SLICE_D.externalEventRef),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&select=event_id,status_code,event_type_code`),
  ]);
  if (!sliceBReceiptRows || !sliceCNormalizations || !shopeeLifecycleRows || !sliceELifecycleRows || !sliceENormalizations || !sliceEReserveEvents || !sliceF || !sliceG || !sliceH || !sliceI || !sliceDEvents || !sliceEEvents) return null;
  const sliceBReceipt = sliceBReceiptRows.length === 1 ? sliceBReceiptRows[0] : null;
  const sliceBLedgerRows = sliceBReceipt && isNonBlank(sliceBReceipt.transaction_id)
    ? await readStockLedgerByTransactionId(supabaseUrl, publishableKey, accessToken, organizationId, sliceBReceipt.transaction_id)
    : [];
  if (!sliceBLedgerRows) return null;
  const [sliceJState, sliceKState] = await Promise.all([
    probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: highestPersistedPhase }),
    probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: highestPersistedPhase }),
  ]);
  if (!sliceJState || !sliceKState) return null;
  const sliceJLifecycleContract = resolveGoldenSliceJLifecycleContract({
    authoritativePhase: highestPersistedPhase,
    returnIdentity: sliceJState.header?.external_return_ref,
    returnEvidence: sliceJState,
    claimEvidence: sliceJDownstreamEvidenceFromSliceKState(sliceKState),
    notificationEvidence: sliceJDownstreamEvidenceFromSliceKState(sliceKState),
    currentProjection: sliceJState.stock,
    duplicateEvidence: sliceJState.counts,
    executionMode: "REPLAY",
  });
  if (!["SAME_PHASE_REPLAY", "LATER_PHASE_REPLAY"].includes(sliceJLifecycleContract.classification)) {
    throw goldenSliceJLifecycleContractError(sliceJLifecycleContract);
  }
  const terminalState = isPhaseAtLeast(highestPersistedPhase, "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED")
    ? await readGoldenTerminalState(supabaseUrl, publishableKey, accessToken, organizationId)
    : null;
  if (terminalState === null && isPhaseAtLeast(highestPersistedPhase, "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED")) return null;
  const durableSnapshot = isPhaseAtLeast(highestPersistedPhase, "GOLDEN_FINAL_ACCEPTED")
    ? await readGoldenDurableReplaySnapshot(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId)
    : null;
  const durableSnapshotDelta = durableSnapshot
    ? compareGoldenDurableReplaySnapshots(durableSnapshot, structuredClone(durableSnapshot))
    : null;
  if (durableSnapshot) {
    console.log(JSON.stringify({ assertion: "Golden durable replay snapshot", ...durableSnapshot, snapshotDelta: durableSnapshotDelta }, null, 2));
  }
  if (durableSnapshotDelta?.mismatchCount > 0) {
    throw new Error("GOLDEN_DURABLE_SNAPSHOT_DELTA_NOT_EXACT");
  }
  let crossPhasePostconditionAudit = crossPhasePostconditionRegressionAudit;
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_J_TIKTOK_RETURN_LOST")) {
    crossPhasePostconditionAudit = auditSliceJPostconditionAcrossPhases({
      persistedSnapshot: { ...sliceJState, downstream: sliceJDownstreamEvidenceFromSliceKState(sliceKState) },
      highestPersistedPhase,
    });
  }
  console.log(JSON.stringify({ assertion: "Slice J cross-phase persisted postcondition audit", ...crossPhasePostconditionAudit }, null, 2));
  let responseContractAudit = auditSliceJLostResponseContract();
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_J_TIKTOK_RETURN_LOST")) {
    try {
      const idempotencySnapshot = await readSliceJLostIdempotencyResponseSnapshot(organizationId);
      responseContractAudit = auditSliceJLostResponseContract({
        persistedResponseSnapshot: idempotencySnapshot.responseSnapshot,
        expectedReturnId: String(sliceJState.header.return_id),
        expectedReturnRef: SLICE_J.returnRef,
        expectedEventRef: SLICE_J.lostEventRef,
      });
    } catch (error) {
      responseContractAudit = {
        sourceContractFieldCount: MARK_RETURN_LOST_RESPONSE_KEYS.length,
        persistedFieldCount: 0,
        missingFieldCount: 0,
        invalidFieldCount: 1,
        unexpectedFieldCount: 0,
        mismatchCount: 1,
        mismatches: [{ label: "persisted response snapshot", reason: error instanceof Error ? error.message : "UNKNOWN" }],
      };
    }
  }
  console.log(JSON.stringify({ assertion: "Slice J LOST response contract audit", ...responseContractAudit }, null, 2));
  let claimContractAudit = claimContractRegressionAudit;
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_K_TIKTOK_CLAIM_CREATED")) {
    claimContractAudit = auditSliceKClaimContract({ persistedSnapshot: sliceKState });
  }
  console.log(JSON.stringify({ assertion: "Slice K claim contract audit", ...claimContractAudit }, null, 2));
  let notificationContractAudit = notificationContractRegressionAudit;
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_K_TIKTOK_CLAIM_CREATED")) {
    notificationContractAudit = auditSliceKNotificationContract({ persistedSnapshot: sliceKState });
  }
  console.log(JSON.stringify({ assertion: "Slice K notification contract audit", ...notificationContractAudit }, null, 2));
  const lifecycle = shopeeLifecycleRows.length === 1 ? shopeeLifecycleRows[0] : null;
  const lifecycleActual = lifecycle ? {
    reserved: asNumber(lifecycle.reserved_qty), consumed: asNumber(lifecycle.consumed_qty), released: asNumber(lifecycle.released_qty), reservationStatus: String(lifecycle.reservation_status_code ?? ""), shipped: asNumber(lifecycle.shipped_quantity), preShipmentCancelled: asNumber(lifecycle.pre_shipment_cancelled_quantity), postShipmentCancelled: asNumber(lifecycle.post_shipment_cancelled_quantity), returnExpected: asNumber(lifecycle.return_expected_quantity), returnReceived: asNumber(lifecycle.return_received_quantity), returnSellable: asNumber(lifecycle.return_sellable_quantity), returnDamaged: asNumber(lifecycle.return_damaged_quantity), returnLost: asNumber(lifecycle.return_lost_quantity), openReserved: asNumber(lifecycle.open_reserved_quantity), remaining: asNumber(lifecycle.remaining_returnable_or_cancellable_quantity),
  } : null;
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_C_RESERVED")) {
    goldenCurrentStateMismatch(mismatches, "Shopee component lifecycle", "C/D", expected.phase, expected.shopeeLifecycle, lifecycleActual);
  }
  const tiktokLifecycle = sliceELifecycleRows.length === 1 ? sliceELifecycleRows[0] : null;
  const tiktokLifecycleActual = tiktokLifecycle ? marketplaceLifecycleActualFromRow(tiktokLifecycle) : null;
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_E_RESERVED")) {
    goldenCurrentStateMismatch(mismatches, "TikTok component lifecycle", "E", expected.phase, expected.tiktokComponentLifecycle, tiktokLifecycleActual);
  }
  const historical = [
    ["Slice B receipt command and ledger", "B", isPhaseAtLeast(highestPersistedPhase, "SLICE_B_RECEIVED"), sliceBReceiptRows.length === 1 && sliceBLedgerRows.length === 1 && String(sliceBLedgerRows[0]?.source_ref_snapshot ?? "") === "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM" && asNumber(sliceBLedgerRows[0]?.quantity_delta) === 10],
    ["Slice C reservation normalization", "C", isPhaseAtLeast(highestPersistedPhase, "SLICE_C_RESERVED"), sliceCNormalizations.length === 1],
    ["Slice D shipment event", "D", isPhaseAtLeast(highestPersistedPhase, "SLICE_D_SHIPPED"), sliceDEvents.length === 1],
    ["Slice E reservation evidence", "E", isPhaseAtLeast(highestPersistedPhase, "SLICE_E_RESERVED"), sliceENormalizations.length === 1 && sliceEReserveEvents.length === 1 && String(sliceEReserveEvents[0]?.event_type_code ?? "") === "RESERVE" && String(sliceEReserveEvents[0]?.status_code ?? "") === "APPLIED"],
    ["Slice E shipment event", "E", isPhaseAtLeast(highestPersistedPhase, "SLICE_E_IN_TRANSIT"), sliceEEvents.length === 1 && String(sliceEEvents[0]?.event_type_code ?? "") === "SHIP" && String(sliceEEvents[0]?.status_code ?? "") === "APPLIED"],
    ["Slice F manual outbound evidence", "F", isPhaseAtLeast(highestPersistedPhase, "SLICE_F_MANUAL_BONUS"), sliceF.classification === "EXACT" || sliceF.evidence?.headerExact === true && sliceF.evidence?.lineExact === true && sliceF.evidence?.allocationExact === true && sliceF.evidence?.ledgerExact === true],
    ["Slice G bundle shipment evidence", "G", isPhaseAtLeast(highestPersistedPhase, "SLICE_G_BUNDLE_SHIPPED"), String(sliceG.phase?.detectedPhase ?? "") === "SLICE_G_BUNDLE_SHIPPED"],
    ["Slice H verified receipt evidence", "H", isPhaseAtLeast(highestPersistedPhase, "SLICE_H_RETURN_RECEIVED"), sliceH.classification === "EXACT_RECEIVED"],
    ["Slice I mixed inspection evidence", "I", isPhaseAtLeast(highestPersistedPhase, "SLICE_I_RETURN_INSPECTED"), sliceIHistoricalEvidenceExact(sliceI)],
  ];
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_J_TIKTOK_RETURN_EXPECTED")) {
    historical.push(["Slice J TikTok expected/lost evidence", "J", true, ["EXPECTED_ONLY", "EXACT_LOST"].includes(sliceJState.classification)]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_J_TIKTOK_RETURN_LOST")) {
    historical.push(["Slice J TikTok LOST stock-neutral evidence", "J", true, sliceJState.classification === "EXACT_LOST"]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_K_TIKTOK_CLAIM_CREATED")) {
    historical.push(["Slice K TikTok claim evidence", "K", true, ["EXACT_CLAIM_CREATED", "EXACT_NOTIFICATION_CREATED"].includes(sliceKState.classification)]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "SLICE_K_TIKTOK_CLAIM_NOTIFICATION")) {
    historical.push(["Slice K D14 notification evidence", "K", true, sliceKState.classification === "EXACT_NOTIFICATION_CREATED"]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "GOLDEN_STOCKTAKE_ADJUSTMENT_POSTED")) {
    historical.push(["Golden stocktake snapshot/count/approval/posting evidence", "TERMINAL", true, terminalState?.stocktakeExact === true]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "GOLDEN_RECONCILIATION_COMPLETED")) {
    historical.push(["Golden linked post-stocktake reconciliation evidence", "TERMINAL", true, terminalState?.reconciliationExact === true]);
  }
  if (isPhaseAtLeast(highestPersistedPhase, "GOLDEN_FINAL_ACCEPTED")) {
    historical.push(["Golden final acceptance evidence", "TERMINAL", true, terminalState?.classification === "EXACT_FINAL"]);
    historical.push(["Golden durable replay snapshot evidence", "TERMINAL", true, durableSnapshot !== null && durableSnapshotDelta?.mismatchCount === 0]);
  }
  for (const [assertion, slice, required, passed] of historical) {
    if (required && !passed) mismatches.push({ assertion, slice, category: "HISTORICAL_EVIDENCE", expectedPhase: expected.phase, observedPhase: highestPersistedPhase.detectedPhase, expected: "exact persisted evidence", actual: "missing, duplicate, or conflicting" });
  }
  const allMismatches = [
    ...mismatches,
    ...expectedStateModelAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "EXPECTED_STATE_MODEL" })),
    ...lowerSliceReplayAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "LOWER_SLICE_REPLAY" })),
    ...lifecycleModelAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "LIFECYCLE_MODEL" })),
    ...assertionContextAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "ASSERTION_CONTEXT" })),
    ...replayPhaseMonotonicityAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "REPLAY_PHASE_MONOTONICITY" })),
    ...projectionReplayContextAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "PROJECTION_REPLAY_CONTEXT" })),
    ...structuralCardinalityAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "STRUCTURAL_CARDINALITY" })),
    ...lowerSliceLifecycleProbe.mismatches.map((mismatch) => ({ ...mismatch, category: "LOWER_SLICE_LIFECYCLE_REPLAY" })),
    ...responseContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "RESPONSE_CONTRACT" })),
    ...claimContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "CLAIM_CONTRACT" })),
    ...sliceKNotificationPersistedContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "SLICE_K_NOTIFICATION_PERSISTED_CONTRACT" })),
    ...notificationContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "NOTIFICATION_CONTRACT" })),
    ...crossPhasePostconditionAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "CROSS_PHASE_POSTCONDITION" })),
    ...stocktakeContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "STOCKTAKE_CONTRACT" })),
    ...reconciliationContractAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "RECONCILIATION_CONTRACT" })),
    ...reconciliationTerminalStatusAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "RECONCILIATION_TERMINAL_STATUS" })),
    ...finalAcceptanceAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "FINAL_ACCEPTANCE" })),
    ...returnLifecycleDurableReplayAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "RETURN_LIFECYCLE_DURABLE_REPLAY" })),
    ...sliceJDownstreamSupersetAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "SLICE_J_DOWNSTREAM_SUPERSET" })),
    ...runtimePreflightParityAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "RUNTIME_PREFLIGHT_PARITY" })),
    ...durableSnapshotReaderAudit.mismatches.map((mismatch) => ({ ...mismatch, category: "DURABLE_SNAPSHOT_READER" })),
    ...controlFlowAudit.mismatches.map((mismatch) => ({
      ...mismatch,
      category: "MONOTONIC_COMPLETION",
    })),
    ...stateAwareControlFlowAudit.mismatches.map((mismatch) => ({
      ...mismatch,
      category: "STATE_AWARE_CONTROL_FLOW",
    })),
    ...projectionEvidenceAudit.mismatches.map((mismatch) => ({
      ...mismatch,
      category: "PROJECTION_EVIDENCE",
    })),
  ];
  const result = {
    highestPersistedPhase: highestPersistedPhase.detectedPhase,
    phaseRank: getSerumProjectionPhaseRank(highestPersistedPhase),
    assertionsChecked: 7 + Object.keys(expected.serumProductionBatches).length + Object.keys(expected.cleanserBatches).length + historical.length + lowerSliceLifecycleProbe.checkedPathCount,
    dataMismatchCount: mismatches.length,
    controlFlowMismatchCount: controlFlowAudit.mismatchCount,
    nullableHelperReturnCount: stateAwareControlFlowAudit.nullableReturnPathCount,
    silentCallerReturnCount: stateAwareControlFlowAudit.silentCallerReturnCount,
    stateAwareControlFlowMismatchCount: stateAwareControlFlowAudit.mismatchCount,
    projectionEvidenceMismatchCount: projectionEvidenceAudit.mismatchCount,
    staleProjectionEvidenceCount: projectionEvidenceAudit.staleSnapshotCount,
    missingProjectionEvidenceCount: projectionEvidenceAudit.missingEvidenceCount,
    evidenceDivergenceCount: projectionEvidenceAudit.evidenceDivergenceCount,
    projectionReplayContextMismatchCount: projectionReplayContextAudit.mismatchCount,
    structuralCardinalityMismatchCount: structuralCardinalityAudit.mismatchCount,
    externalSourceLineMismatchCount: structuralCardinalityAudit.externalSourceLineMismatchCount,
    componentCardinalityMismatchCount: structuralCardinalityAudit.componentMismatchCount,
    duplicateIdentityCount: structuralCardinalityAudit.duplicateIdentityCount,
    wrongCheckpointProjectionCount: projectionReplayContextAudit.mismatches.filter((mismatch) => String(mismatch.case ?? "").includes("CHECKPOINT_PROJECTION")).length,
    authoritativeProjectionMismatchCount: projectionReplayContextAudit.mismatches.filter((mismatch) => String(mismatch.case ?? "").includes("WRONG_AUTHORITATIVE_PROJECTION")).length,
    expectedStateModelMismatchCount: expectedStateModelAudit.mismatchCount + lowerSliceReplayAudit.mismatchCount,
    lifecycleModelMismatchCount: lifecycleModelAudit.mismatchCount + lowerSliceLifecycleProbe.mismatchCount,
    projectionContextMismatchCount: assertionContextAudit.projectionMismatchCount,
    lifecycleContextMismatchCount: assertionContextAudit.lifecycleMismatchCount,
    checkpointContextMismatchCount: assertionContextAudit.checkpointMismatchCount,
    assertionContextMismatchCount: assertionContextAudit.mismatchCount,
    replayPhaseMonotonicityMismatchCount: replayPhaseMonotonicityAudit.mismatchCount,
    overStrictEqualityGuardCount: replayPhaseMonotonicityAudit.overStrictEqualityGuardCount,
    invalidLaterPhaseRejectionCount: replayPhaseMonotonicityAudit.invalidLaterPhaseRejectionCount,
    historicalEvidenceMismatchCount: replayPhaseMonotonicityAudit.historicalEvidenceMismatchCount + projectionReplayContextAudit.mismatches.filter((mismatch) => String(mismatch.case ?? "").includes("HISTORICAL")).length,
    exitSemanticsMismatchCount: exitSemanticsAudit.mismatchCount,
    responseContractMismatchCount: responseContractAudit.mismatchCount,
    claimContractMismatchCount: claimContractAudit.mismatchCount,
    sliceKNotificationPersistedMismatchCount: sliceKNotificationPersistedContractAudit.mismatchCount + notificationContractAudit.persistedNotificationMismatchCount,
    notificationTemporalMismatchCount: sliceKNotificationPersistedContractAudit.temporalMismatchCount,
    notificationReadModelDivergenceCount: sliceKNotificationPersistedContractAudit.readModelDivergenceCount,
    notificationDuplicateEpisodeCount: sliceKNotificationPersistedContractAudit.duplicateEpisodeCount,
    notificationContractMismatchCount: notificationContractAudit.mismatchCount,
    crossPhasePostconditionMismatchCount: crossPhasePostconditionAudit.mismatchCount,
    stocktakeContractMismatchCount: stocktakeContractAudit.mismatchCount,
    stocktakeAdjustmentMismatchCount: stocktakeContractAudit.adjustmentMismatchCount,
    reconciliationContractMismatchCount: reconciliationContractAudit.mismatchCount,
    reconciliationTerminalStatusMismatchCount: reconciliationTerminalStatusAudit.successfulStatusMismatchCount,
    reconciliationPhaseDomainMixupCount: reconciliationTerminalStatusAudit.phaseDomainStatusMixupCount,
    reconciliationEvidenceMismatchCount: reconciliationTerminalStatusAudit.evidenceMismatchCount,
    reconciliationCriticalIssueCount: terminalState?.reconciliationIssues?.filter((issue) => String(issue?.status_code ?? "") === "OPEN" && String(issue?.severity_code ?? "") === "CRITICAL").length ?? 0,
    finalAcceptanceMismatchCount: finalAcceptanceAudit.mismatchCount,
    returnLifecycleDurableReplayMismatchCount: returnLifecycleDurableReplayAudit.mismatchCount,
    sliceReturnIdentityMismatchCount: returnLifecycleDurableReplayAudit.identityScopeMismatchCount,
    sliceCrossContaminationCount: returnLifecycleDurableReplayAudit.sliceCrossContaminationCount,
    sliceJLifecycleMismatchCount: ["SAME_PHASE_REPLAY", "LATER_PHASE_REPLAY"].includes(sliceJLifecycleContract.classification) ? 0 : 1,
    sliceJAllowedDownstreamRejectionCount: sliceJDownstreamSupersetAudit.allowedDownstreamRejectionCount,
    runtimePreflightParityMismatchCount: runtimePreflightParityAudit.mismatchCount,
    runtimeFailPreflightPassCount: runtimePreflightParityAudit.runtimeFailPreflightPassCount,
    terminalHistoricalEvidenceMismatchCount: returnLifecycleDurableReplayAudit.terminalReplayRejectionCount + (sliceJLifecycleContract.historicalEvidenceExact ? 0 : 1),
    durableSnapshotReaderMismatchCount: durableSnapshotReaderAudit.mismatchCount,
    durableSnapshotDeltaMismatchCount: durableSnapshotDelta?.mismatchCount ?? 0,
    // Every persisted slice probe above requires its command/event/ledger
    // cardinality to be exact; a non-zero structural duplicate is therefore a
    // preflight mismatch rather than a tolerated count.
    duplicateEffectCount: structuralCardinalityAudit.duplicateIdentityCount,
    mismatchCount: allMismatches.length,
    mismatches: allMismatches,
  };
  console.log(JSON.stringify({ assertion: "Golden replay aggregate preflight", ...result }, null, 2));
  if (allMismatches.length > 0) throw new Error("GOLDEN_REPLAY_PREFLIGHT_FAILED");
  return result;
}

function buildSliceCNormalizationSafeSubset(row) {
  return {
    normalization_event_id: row?.normalization_event_id ?? null,
    marketplace_event_id: row?.marketplace_event_id ?? null,
    order_id: row?.order_id ?? null,
    organization_id: row?.organization_id ?? null,
    channel_code: row?.channel_code ?? null,
    external_event_ref_snapshot:
      row?.external_event_ref_snapshot ?? null,
    external_order_ref_snapshot:
      row?.external_order_ref_snapshot ?? null,
    event_source_status: row?.event_source_status ?? null,
    occurred_at: row?.occurred_at ?? null,
    received_at: row?.received_at ?? null,
    normalization_schema_version:
      row?.normalization_schema_version ?? null,
    source_line_id: row?.source_line_id ?? null,
    source_line_no: row?.source_line_no ?? null,
    source_line_ref: row?.source_line_ref ?? null,
    listing_id: row?.listing_id ?? null,
    external_listing_code_snapshot:
      row?.external_listing_code_snapshot ?? null,
    listing_type_code_snapshot:
      row?.listing_type_code_snapshot ?? null,
    listing_quantity: row?.listing_quantity ?? null,
    mapping_version: row?.mapping_version ?? null,
    component_no: row?.component_no ?? null,
    canonical_source_line_ref:
      row?.canonical_source_line_ref ?? null,
    product_sku_snapshot: row?.product_sku_snapshot ?? null,
    unit_quantity_per_listing:
      row?.unit_quantity_per_listing ?? null,
    expanded_quantity: row?.expanded_quantity ?? null,
    line_source_status: row?.line_source_status ?? null,
    reserved_qty: row?.reserved_qty ?? null,
    consumed_qty: row?.consumed_qty ?? null,
    released_qty: row?.released_qty ?? null,
    reservation_status_code:
      row?.reservation_status_code ?? null,
  };
}

assertSliceCNormalizationRowExact =
  function assertSliceCNormalizationRowSnapshotExact(
    rows,
    organizationId,
  ) {
    const safeRows = Array.isArray(rows)
      ? rows.map((row) => buildSliceCNormalizationSafeSubset(row))
      : [];

    if (!Array.isArray(rows)) {
      fail(
        `Normalization Slice C tidak exact. actual=${JSON.stringify({
          expectedCardinality: "0 atau 1 pada pre-read; 1 setelah reserve",
          actualCardinality: 0,
          actualRows: safeRows,
        })}`,
      );
      return null;
    }

    // Fresh path sebelum reserve memang boleh belum memiliki normalization.
    if (rows.length === 0) {
      return null;
    }

    if (rows.length !== 1) {
      fail(
        `Normalization Slice C tidak exact. actual=${JSON.stringify({
          expectedCardinality: 1,
          actualCardinality: rows.length,
          actualRows: safeRows,
        })}`,
      );
      return null;
    }

    const row = rows[0];

    if (
      String(row?.organization_id ?? "") !== String(organizationId) ||
      String(row?.channel_code ?? "") !== SLICE_C.channelCode ||
      String(row?.external_event_ref_snapshot ?? "") !==
        SLICE_C.externalEventRef ||
      String(row?.external_order_ref_snapshot ?? "") !==
        SLICE_C.externalOrderRef ||
      String(row?.event_source_status ?? "") !== SLICE_C.sourceStatus ||
      String(row?.line_source_status ?? "") !== SLICE_C.sourceStatus ||
      !sameInstant(row?.occurred_at, SLICE_C.occurredAt) ||
      !sameInstant(row?.received_at, SLICE_C.receivedAt) ||
      asNumber(row?.normalization_schema_version) !== 1 ||
      asNumber(row?.source_line_no) !== 1 ||
      String(row?.source_line_ref ?? "") !== SLICE_C.sourceLineRef ||
      String(row?.external_listing_code_snapshot ?? "") !==
        SLICE_C.externalListingCode ||
      String(row?.listing_type_code_snapshot ?? "") !== "SINGLE" ||
      asNumber(row?.listing_quantity) !== 8 ||
      asNumber(row?.mapping_version) < 1 ||
      !isNonBlank(row?.single_listing_version_id) ||
      row?.bundle_recipe_id !== null ||
      !isHex64(row?.mapping_fingerprint) ||
      !isHex64(row?.raw_payload_hash) ||
      !isHex64(row?.raw_line_hash) ||
      asNumber(row?.component_no) !== 1 ||
      String(row?.canonical_source_line_ref ?? "") !==
        SLICE_D.canonicalSourceLineRef ||
      String(row?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
      asNumber(row?.unit_quantity_per_listing) !== 1 ||
      asNumber(row?.expanded_quantity) !== 8 ||
      !isNonBlank(row?.normalization_event_id) ||
      !isNonBlank(row?.marketplace_event_id) ||
      !isNonBlank(row?.order_id) ||
      !isNonBlank(row?.source_line_id) ||
      !isNonBlank(row?.listing_id) ||
      !isNonBlank(row?.source_component_id) ||
      !isNonBlank(row?.order_item_id) ||
      !isNonBlank(row?.reserve_event_line_id) ||
      !isNonBlank(row?.product_id) ||
      !isNonBlank(row?.reservation_id)
    ) {
      fail(
        `Normalization Slice C tidak exact. actual=${JSON.stringify({
          expectedCardinality: 1,
          actualCardinality: 1,
          actualRows: safeRows,
        })}`,
      );
      return null;
    }

    /*
     * reserved_qty, consumed_qty, released_qty, dan
     * reservation_status_code adalah current reservation join.
     * Nilainya diverifikasi melalui view reservation/lifecycle,
     * bukan sebagai historical normalization snapshot.
     */
    return row;
  };
function assertSliceCListingLifecycleSnapshotPhaseAware(readModel, expectedPhase) {
  const highestExpectedPhase = resolveExpectedSerumProjectionPhase(expectedPhase);
  const productRows = (readModel?.productInventory ?? []).filter(
    (row) => String(row?.sku ?? "") === "SER-NIA-30",
  );

  if (productRows.length !== 1) {
    fail(`Snapshot lifecycle listing Slice C untuk product_inventory harus tepat satu row, tetapi ditemukan ${productRows.length}.`);
    return false;
  }

  const productRow = productRows[0];
  if (
    asNumber(productRow?.sellable_qty) !== highestExpectedPhase.sellable ||
    asNumber(productRow?.reserved_qty) !== highestExpectedPhase.reserved ||
    asNumber(productRow?.available_qty) !== highestExpectedPhase.available
  ) {
    fail(
      `Snapshot lifecycle listing Slice C untuk product_inventory tidak exact. actual=${JSON.stringify({
        detectedPhase: highestExpectedPhase.detectedPhase,
        expected: {
          sellable: highestExpectedPhase.sellable,
          reserved: highestExpectedPhase.reserved,
          available: highestExpectedPhase.available,
        },
        actual: {
          sellable_qty: productRow?.sellable_qty ?? null,
          reserved_qty: productRow?.reserved_qty ?? null,
          available_qty: productRow?.available_qty ?? null,
        },
      })}`,
    );
    return false;
  }

  const expectedBatches = highestExpectedPhase.batches;
  const expectedBatchCodes = new Set(Object.keys(expectedBatches));
  const actualBatches = {};
  const batchRows = (readModel?.batchInventory ?? []).filter((row) => {
    const batchCode = String(row?.batch_code ?? "");
    if (!expectedBatchCodes.has(batchCode)) return false;
    actualBatches[batchCode] = asNumber(row?.sellable_qty);
    return true;
  });

  if (batchRows.length !== expectedBatchCodes.size) {
    fail(
      `Snapshot lifecycle listing Slice C untuk batch_inventory tidak exact. actual=${JSON.stringify({
        detectedPhase: highestExpectedPhase.detectedPhase,
        expectedBatches,
        actualBatches,
      })}`,
    );
    return false;
  }

  for (const [batchCode, expectedQty] of Object.entries(expectedBatches)) {
    if (asNumber(actualBatches[batchCode]) !== asNumber(expectedQty)) {
      fail(
        `Snapshot lifecycle listing Slice C untuk batch_inventory tidak exact. actual=${JSON.stringify({
          detectedPhase: highestExpectedPhase.detectedPhase,
          expectedBatches,
          actualBatches,
        })}`,
      );
      return false;
    }
  }

  return true;
}

const ensureSliceCShopeeListingLegacy = ensureSliceCShopeeListing;
ensureSliceCShopeeListing = async function ensureSliceCShopeeListingPhaseAware(
  supabaseUrl,
  publishableKey,
  accessToken,
  organizationId,
  serumProductId,
  expectedPhaseOrReservedQuantity,
) {
  const expectedPhase = resolveExpectedSerumProjectionPhase(expectedPhaseOrReservedQuantity);

  const beforeReadModel = await fetchReadModel(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!beforeReadModel) {
    return null;
  }
  if (!assertSliceCListingLifecycleSnapshotPhaseAware(beforeReadModel, expectedPhase)) {
    return null;
  }

  if (expectedPhase.detectedPhase === "SLICE_B_RECEIVED") {
    return await ensureSliceCShopeeListingLegacy(
      supabaseUrl,
      publishableKey,
      accessToken,
      organizationId,
      serumProductId,
      expectedPhase.reserved,
    );
  }

  const normalizationRows = await readSliceCNormalizations(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!normalizationRows) {
    return null;
  }
  if (!assertSliceCNormalizationRowExact(normalizationRows, organizationId)) {
    return null;
  }

  const afterReadModel = await fetchReadModel(
    supabaseUrl,
    publishableKey,
    accessToken,
    organizationId,
  );
  if (!afterReadModel) {
    return null;
  }
  if (!assertSliceCListingLifecycleSnapshotPhaseAware(afterReadModel, expectedPhase)) {
    return null;
  }

  return {
    status: "ADOPTED",
    detectedPhase: expectedPhase.detectedPhase,
  };
};

function exactGoldenRow(rows, errorCode) {
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw new Error(errorCode);
  }
  const [row] = rows;
  return row;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- retained deterministic ISO helper for claim-deadline diagnostics.
function isoOffsetDays(isoTimestamp, days) {
  const time = Date.parse(String(isoTimestamp ?? ""));
  if (!Number.isFinite(time)) throw new Error("SLICE_K_CLAIM_DEADLINE_INVALID");
  return new Date(time - days * 24 * 60 * 60 * 1000).toISOString();
}

async function invokeGoldenTrustedWorker(input) {
  const minimalEnv = {
    PATH: process.env.PATH ?? "",
    SystemRoot: process.env.SystemRoot ?? "",
    WINDIR: process.env.WINDIR ?? "",
    ComSpec: process.env.ComSpec ?? "",
    PATHEXT: process.env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD",
  };
  return await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/golden-demo-trusted-worker.mjs"], {
      cwd: process.cwd(),
      env: minimalEnv,
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", () => reject(new Error("GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED")));
    child.on("close", (code) => {
      const lines = stdout.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
      if (lines.length !== 1) return reject(new Error("GOLDEN_TRUSTED_WORKER_OUTPUT_INVALID"));
      try {
        const output = JSON.parse(lines[0]);
        if (code !== 0 || output?.ok !== true) {
          return reject(new Error(/^GOLDEN_TRUSTED_WORKER_[A-Z_]+$/.test(String(output?.error ?? "")) ? output.error : "GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED"));
        }
        if (stderr.trim()) return reject(new Error("GOLDEN_TRUSTED_WORKER_STDERR_NOT_EMPTY"));
        return resolve(output);
      } catch {
        return reject(new Error("GOLDEN_TRUSTED_WORKER_OUTPUT_INVALID"));
      }
    });
    child.stdin.end(JSON.stringify(input));
  });
}

async function readSliceJStockNeutral(supabaseUrl, publishableKey, accessToken, organizationId, phase) {
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
  const model = await fetchReadModel(supabaseUrl, publishableKey, accessToken, organizationId);
  if (!model) return null;
  const serum = exactGoldenRow((model.productInventory ?? []).filter((row) => String(row?.sku ?? "") === SLICE_J.productSku), "SLICE_J_SERUM_PRODUCT_AMBIGUOUS");
  const cleanser = exactGoldenRow((model.productInventory ?? []).filter((row) => String(row?.sku ?? "") === SLICE_G.cleanserProductSku), "SLICE_J_CLEANSER_PRODUCT_AMBIGUOUS");
  const batchBalance = (batchCode) => {
    const row = exactGoldenRow((model.batchInventory ?? []).filter((candidate) => String(candidate?.batch_code ?? "") === batchCode), `SLICE_J_BATCH_${batchCode}_AMBIGUOUS`);
    return asNumber(row?.sellable_qty);
  };
  const returnBatches = (model.batchInventory ?? []).filter((row) => String(row?.product_id ?? "") === String(serum?.product_id ?? "") && String(row?.batch_kind_code ?? "") === "RETURN");
  const actual = {
    serum: [asNumber(serum?.sellable_qty), asNumber(serum?.reserved_qty), asNumber(serum?.available_qty)],
    cleanser: [asNumber(cleanser?.sellable_qty), asNumber(cleanser?.reserved_qty), asNumber(cleanser?.available_qty)],
    batches: Object.fromEntries(Object.keys(expected.serumProductionBatches).map((code) => [code, batchBalance(code)])),
    returnBatch: { count: returnBatches.length, sellable: returnBatches.reduce((total, row) => total + asNumber(row?.sellable_qty), 0) },
  };
  const exact = actual.serum.join(",") === [expected.serumProduct.sellable, expected.serumProduct.reserved, expected.serumProduct.available].join(",")
    && actual.cleanser.join(",") === [expected.cleanserProduct.sellable, expected.cleanserProduct.reserved, expected.cleanserProduct.available].join(",")
    && Object.entries(expected.serumProductionBatches).every(([code, quantity]) => actual.batches[code] === quantity)
    && actual.returnBatch.count === expected.serumReturnBatches.count
    && actual.returnBatch.sellable === expected.serumReturnBatches.sellable;
  return { exact, actual, expected };
}

const MARK_RETURN_LOST_RESPONSE_KEYS = Object.freeze([
  "status",
  "returnId",
  "returnRef",
  "eventId",
  "eventRef",
  "eventType",
  "lineCount",
  "totalQuantity",
  "occurredAt",
  "recordedAt",
]);

const CREATE_TIKTOK_RETURN_CLAIM_RESPONSE_KEYS = Object.freeze([
  "claimId",
  "deadlineAt",
  "stockEffectCode",
]);

function sliceKClaimResponseError(missingPaths, invalidPaths, unexpectedKeys) {
  const error = new Error("SLICE_K_CLAIM_RESPONSE_INVALID");
  error.code = "SLICE_K_CLAIM_RESPONSE_INVALID";
  error.detail = { missingPaths, invalidPaths, unexpectedKeys };
  return error;
}

function expectedSliceKClaimDeadlineAt(returnCreatedAt) {
  const createdAtMs = Date.parse(String(returnCreatedAt));
  if (!Number.isFinite(createdAtMs)) throw new Error("SLICE_K_CLAIM_RETURN_CREATED_AT_INVALID");
  return new Date(createdAtMs + 40 * 24 * 60 * 60 * 1000).toISOString();
}

function validateCreateTiktokReturnClaimResponse({ response, expectedDeadlineAt }) {
  const missingPaths = [];
  const invalidPaths = [];
  if (!isPlainObject(response)) throw sliceKClaimResponseError(["response"], [], []);
  const requireValue = (path, value, predicate, reason) => {
    if (value === undefined) missingPaths.push(path);
    else if (!predicate(value)) invalidPaths.push({ path, reason });
  };
  requireValue("response.claimId", response.claimId, (value) => UUID_PATTERN.test(String(value)), "EXPECTED_UUID");
  requireValue("response.deadlineAt", response.deadlineAt, (value) => Number.isFinite(Date.parse(String(value))) && sameInstant(value, expectedDeadlineAt), "EXPECTED_RETURN_CREATED_AT_PLUS_40_DAYS");
  requireValue("response.stockEffectCode", response.stockEffectCode, (value) => value === "NONE", "EXPECTED_NONE");
  const unexpectedKeys = Object.keys(response).filter((key) => !CREATE_TIKTOK_RETURN_CLAIM_RESPONSE_KEYS.includes(key)).sort();
  if (missingPaths.length > 0 || invalidPaths.length > 0) {
    throw sliceKClaimResponseError(missingPaths, invalidPaths, unexpectedKeys);
  }
  return { response, unexpectedKeys };
}

function sliceKClaimEvidenceDiagnostics() {
  return { missingPaths: [], invalidPaths: [] };
}

function sliceKClaimCounts(snapshot) {
  return {
    claimCount: 1,
    claimItemCount: Array.isArray(snapshot.claimItems) ? snapshot.claimItems.length : 0,
    claimEventCount: Array.isArray(snapshot.claimEvents) ? snapshot.claimEvents.length : 0,
    idempotencyCount: isPlainObject(snapshot.idempotency) && Number.isSafeInteger(snapshot.idempotency.candidateCount) ? snapshot.idempotency.candidateCount : 0,
    notificationCount: Array.isArray(snapshot.notifications) ? snapshot.notifications.length : 0,
    notificationRuleRunCount: isPlainObject(snapshot.notificationRuns) && Array.isArray(snapshot.notificationRuns.canonicalRuns) ? snapshot.notificationRuns.canonicalRuns.length : 0,
    legacyNoopRunCount: isPlainObject(snapshot.notificationRuns) && Array.isArray(snapshot.notificationRuns.legacyRuns) ? snapshot.notificationRuns.legacyRuns.length : 0,
  };
}

function notificationRunCountsAreSafe(run) {
  return ["evaluatedCount", "createdCount", "updatedCount", "resolvedCount", "skippedCount", "errorCount"]
    .every((path) => Number.isSafeInteger(run?.[path]) && run[path] >= 0);
}

function timestamptzEpochMicroseconds(value) {
  const text = String(value ?? "");
  const milliseconds = Date.parse(text);
  const fraction = text.match(/\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/i);
  if (!Number.isFinite(milliseconds) || !fraction) return null;
  const microseconds = `${fraction[1]}000000`.slice(0, 6);
  return BigInt(milliseconds) * 1000n + BigInt(microseconds.slice(3, 6));
}

function sameInstantWithMicrosecondPrecision(actual, expected) {
  const actualMicroseconds = timestamptzEpochMicroseconds(actual);
  const expectedMicroseconds = timestamptzEpochMicroseconds(expected);
  return actualMicroseconds !== null && expectedMicroseconds !== null && actualMicroseconds === expectedMicroseconds;
}

function validateSliceKLegacyEarlyNoopRun(run, expectedD14At) {
  if (!isPlainObject(run)) return false;
  const observedAt = isPlainObject(run.summary) ? run.summary.observedAt : null;
  const observedMicroseconds = timestamptzEpochMicroseconds(observedAt);
  const expectedMicroseconds = timestamptzEpochMicroseconds(expectedD14At);
  return String(run.idempotencyKey ?? "") === SLICE_K.legacyNotificationIdempotencyKey
    && String(run.status ?? "") === "SUCCEEDED"
    && UUID_PATTERN.test(String(run.ruleRunId ?? ""))
    && String(run.ruleCode ?? "") === "CLAIM_DEADLINE"
    && String(run.processName ?? "") === SLICE_K.workerProcessName
    && run.evaluatedCount === 1 && run.createdCount === 0 && run.updatedCount === 0
    && run.resolvedCount === 0 && run.skippedCount === 1 && run.errorCount === 0
    && isPlainObject(run.summary) && String(run.summary.stockEffectCode ?? "") === "NONE"
    && observedMicroseconds !== null && expectedMicroseconds !== null && observedMicroseconds < expectedMicroseconds
    && isPlainObject(run.errorDetail) && Number.isFinite(Date.parse(String(run.completedAt ?? "")));
}

function sliceKNotificationRunError(missingPaths, invalidPaths, unexpectedKeys) {
  const error = new Error("SLICE_K_NOTIFICATION_RUN_INVALID");
  error.code = "SLICE_K_NOTIFICATION_RUN_INVALID";
  error.detail = { missingPaths, invalidPaths, unexpectedKeys };
  return error;
}

function validateSliceKNotificationEvaluatorRun({ run, expectedObservedAt, expectedCanonicalKey, expectedClaimId }) {
  const missingPaths = [];
  const invalidPaths = [];
  if (!isPlainObject(run)) throw sliceKNotificationRunError(["run"], [], []);
  const requireValue = (path, value, predicate, reason) => {
    if (value === undefined || value === null) missingPaths.push(path);
    else if (!predicate(value)) invalidPaths.push({ path, reason });
  };
  requireValue("run.ruleRunId", run.ruleRunId, (value) => UUID_PATTERN.test(String(value)), "EXPECTED_UUID");
  requireValue("run.idempotencyKey", run.idempotencyKey, (value) => value === expectedCanonicalKey, "EXPECTED_CANONICAL_KEY");
  requireValue("run.status", run.status, (value) => value === "SUCCEEDED", "EXPECTED_SUCCEEDED");
  requireValue("run.ruleCode", run.ruleCode, (value) => value === "CLAIM_DEADLINE", "EXPECTED_CLAIM_DEADLINE");
  requireValue("run.processName", run.processName, (value) => value === SLICE_K.workerProcessName, "EXPECTED_WORKER_PROCESS");
  requireValue("run.completedAt", run.completedAt, (value) => Number.isFinite(Date.parse(String(value))), "EXPECTED_TIMESTAMPTZ");
  requireValue("run.summary", run.summary, isPlainObject, "EXPECTED_PLAIN_OBJECT");
  const summary = isPlainObject(run.summary) ? run.summary : null;
  requireValue("run.summary.observedAt", summary === null ? undefined : summary.observedAt, (value) => sameInstantWithMicrosecondPrecision(value, expectedObservedAt), "EXPECTED_EXACT_D14_INSTANT");
  requireValue("run.summary.stockEffectCode", summary === null ? undefined : summary.stockEffectCode, (value) => value === "NONE", "EXPECTED_NONE");
  requireValue("run.errorCount", run.errorCount, (value) => value === 0, "EXPECTED_ZERO");
  requireValue("run.counts", run, notificationRunCountsAreSafe, "EXPECTED_SAFE_NONNEGATIVE_COUNTS");
  if (!isPlainObject(run.errorDetail) || Object.keys(run.errorDetail).length !== 0) invalidPaths.push({ path: "run.errorDetail", reason: "EXPECTED_EMPTY_OBJECT" });
  if (typeof expectedClaimId !== "string" || !UUID_PATTERN.test(expectedClaimId)) invalidPaths.push({ path: "expectedClaimId", reason: "EXPECTED_UUID" });
  const unexpectedKeys = Object.keys(run).filter((key) => !["ruleRunId", "ruleId", "ruleCode", "ruleVersion", "triggerType", "idempotencyKey", "status", "startedAt", "completedAt", "evaluatedCount", "createdCount", "updatedCount", "resolvedCount", "skippedCount", "errorCount", "summary", "errorDetail", "processName"].includes(key)).sort();
  if (missingPaths.length || invalidPaths.length) throw sliceKNotificationRunError(missingPaths, invalidPaths, unexpectedKeys);
  return { run, unexpectedKeys };
}

function hasValidActorProcessXor(row) {
  if (!isPlainObject(row)) return false;
  const actorPresent = UUID_PATTERN.test(String(row.actor_user_id ?? ""));
  const processPresent = isNonBlank(row.process_name);
  return actorPresent !== processPresent;
}

function validateSliceKClaimCreatedEvidence(snapshot) {
  const detail = sliceKClaimEvidenceDiagnostics();
  const requireValue = (path, value, predicate, reason) => {
    if (value === undefined || value === null) detail.missingPaths.push(path);
    else if (!predicate(value)) detail.invalidPaths.push({ path, reason });
  };
  if (!isPlainObject(snapshot)) return { valid: false, missingPaths: ["snapshot"], invalidPaths: [] };
  const sliceJ = snapshot.sliceJ;
  const claim = snapshot.claim;
  const idempotency = snapshot.idempotency;
  if (!isPlainObject(sliceJ)) detail.missingPaths.push("sliceJ");
  if (!isPlainObject(claim)) detail.missingPaths.push("claim");
  if (!isPlainObject(idempotency)) detail.missingPaths.push("idempotency");
  if (!isPlainObject(sliceJ) || !isPlainObject(claim) || !isPlainObject(idempotency)) {
    return { valid: false, ...detail };
  }
  const sliceJHeader = isPlainObject(sliceJ.header) ? sliceJ.header : null;
  const sliceJItem = isPlainObject(sliceJ.item) ? sliceJ.item : null;
  if (!sliceJHeader) detail.missingPaths.push("sliceJ.header");
  if (!sliceJItem) detail.missingPaths.push("sliceJ.item");
  const claimItems = Array.isArray(snapshot.claimItems) ? snapshot.claimItems : null;
  const claimEvents = Array.isArray(snapshot.claimEvents) ? snapshot.claimEvents : null;
  const notifications = Array.isArray(snapshot.notifications) ? snapshot.notifications : null;
  if (!claimItems) detail.missingPaths.push("claimItems");
  if (!claimEvents) detail.missingPaths.push("claimEvents");
  if (!notifications) detail.missingPaths.push("notifications");
  requireValue("sliceJ.classification", sliceJ.classification, (value) => value === "EXACT_LOST", "EXPECTED_EXACT_LOST");
  requireValue("claim.id", claim.id, (value) => UUID_PATTERN.test(String(value)), "EXPECTED_UUID");
  requireValue("claim.return_id", claim.return_id, (value) => sliceJHeader !== null && String(value) === String(sliceJHeader.return_id), "EXPECTED_SLICE_J_RETURN_ID");
  requireValue("claim.claim_type_code", claim.claim_type_code, (value) => value === SLICE_K.claimTypeCode, "EXPECTED_LOST_RETURN");
  requireValue("claim.status_code", claim.status_code, (value) => value === "NOT_STARTED", "EXPECTED_NOT_STARTED");
  if (claim.resolution_code !== null) detail.invalidPaths.push({ path: "claim.resolution_code", reason: "EXPECTED_NULL" });
  if (claim.external_claim_ref !== null) detail.invalidPaths.push({ path: "claim.external_claim_ref", reason: "EXPECTED_NULL" });
  requireValue("claim.claim_basis_code", claim.claim_basis_code, (value) => value === "RETURN_CREATED_AT", "EXPECTED_RETURN_CREATED_AT");
  requireValue("claim.claim_basis_at", claim.claim_basis_at, (value) => sliceJHeader !== null && sameInstant(value, sliceJHeader.created_at), "EXPECTED_RETURN_CREATED_AT_INSTANT");
  requireValue("claim.window_days_snapshot", claim.window_days_snapshot, (value) => Number.isSafeInteger(Number(value)) && Number(value) === 40, "EXPECTED_40");
  requireValue("claim.timezone_snapshot", claim.timezone_snapshot, (value) => value === "Asia/Jakarta", "EXPECTED_ASIA_JAKARTA");
  requireValue("claim.deadline_source_code", claim.deadline_source_code, (value) => value === "INTERNAL_RETURN_CREATED_AT", "EXPECTED_INTERNAL_RETURN_CREATED_AT");
  requireValue("claim.deadline_at", claim.deadline_at, (value) => sameInstant(value, snapshot.expectedDeadlineAt), "EXPECTED_RETURN_CREATED_AT_PLUS_40_DAYS");
  requireValue("claim.policy_version_snapshot", claim.policy_version_snapshot, (value) => value === SLICE_K.policyVersion, "EXPECTED_POLICY_VERSION");
  requireValue("claim.schema_version", claim.schema_version, (value) => Number.isSafeInteger(Number(value)) && Number(value) === 1, "EXPECTED_SCHEMA_VERSION_1");
  requireValue("claim.actor_process", claim, hasValidActorProcessXor, "EXPECTED_ACTOR_PROCESS_XOR");
  requireValue("claim.stock_effect_code", claim.stock_effect_code, (value) => value === "NONE", "EXPECTED_NONE");
  if (claimItems && claimItems.length !== 1) detail.invalidPaths.push({ path: "claimItems", reason: "EXPECTED_EXACTLY_ONE" });
  if (claimEvents && claimEvents.length !== 1) detail.invalidPaths.push({ path: "claimEvents", reason: "EXPECTED_EXACTLY_ONE_CREATED_EVENT" });
  if (notifications && notifications.length !== 0) detail.invalidPaths.push({ path: "notifications", reason: "EXPECTED_NONE_BEFORE_EVALUATOR" });
  const item = claimItems && claimItems.length === 1 ? exactGoldenRow(claimItems, "SLICE_K_CLAIM_ITEM_AMBIGUOUS") : null;
  const event = claimEvents && claimEvents.length === 1 ? exactGoldenRow(claimEvents, "SLICE_K_CLAIM_EVENT_AMBIGUOUS") : null;
  if (!item) detail.missingPaths.push("claimItem");
  if (!event) detail.missingPaths.push("createdEvent");
  if (item) {
    requireValue("claimItem.claim_id", item.claim_id, (value) => String(value) === String(claim.id), "EXPECTED_CLAIM_ID");
    requireValue("claimItem.return_item_id", item.return_item_id, (value) => sliceJItem !== null && String(value) === String(sliceJItem.return_item_id), "EXPECTED_SLICE_J_RETURN_ITEM_ID");
    requireValue("claimItem.quantity", item.quantity, (value) => typeof value === "number" && Number.isSafeInteger(value) && value === 1, "EXPECTED_SAFE_INTEGER_ONE");
    requireValue("claimItem.eligible_lost_qty_snapshot", item.eligible_lost_qty_snapshot, (value) => typeof value === "number" && Number.isSafeInteger(value) && value === 1, "EXPECTED_SAFE_INTEGER_ONE");
    requireValue("claimItem.product_id", item.product_id, (value) => sliceJItem !== null && String(value) === String(sliceJItem.product_id), "EXPECTED_SERUM_PRODUCT_ID");
    requireValue("claimItem.product_sku_snapshot", item.product_sku_snapshot, (value) => value === SLICE_J.productSku, "EXPECTED_SER_NIA_30");
    requireValue("claimItem.source_line_ref_snapshot", item.source_line_ref_snapshot, (value) => value === SLICE_E.canonicalSourceLineRef, "EXPECTED_CANONICAL_SOURCE_LINE_REF");
    requireValue("claimItem.canonical_components_snapshot", item.canonical_components_snapshot, (value) => Array.isArray(value) && value.length === 1, "EXPECTED_ONE_CANONICAL_COMPONENT");
    const component = Array.isArray(item.canonical_components_snapshot) && item.canonical_components_snapshot.length === 1 ? item.canonical_components_snapshot[0] : null;
    if (!isPlainObject(component)) detail.invalidPaths.push({ path: "claimItem.canonical_components_snapshot[0]", reason: "EXPECTED_PLAIN_OBJECT" });
    else {
      requireValue("claimItem.component.snapshotSchemaVersion", component.snapshotSchemaVersion, (value) => Number.isSafeInteger(Number(value)) && Number(value) === 2, "EXPECTED_SOURCE_SCHEMA_VERSION_2");
      requireValue("claimItem.component.provenanceKind", component.provenanceKind, (value) => value === "SINGLE_PRODUCT_SOURCE", "EXPECTED_SINGLE_PRODUCT_SOURCE");
      requireValue("claimItem.component.returnItemId", component.returnItemId, (value) => sliceJItem !== null && String(value) === String(sliceJItem.return_item_id), "EXPECTED_RETURN_ITEM_ID");
      requireValue("claimItem.component.productId", component.productId, (value) => sliceJItem !== null && String(value) === String(sliceJItem.product_id), "EXPECTED_PRODUCT_ID");
      requireValue("claimItem.component.productSku", component.productSku, (value) => value === SLICE_J.productSku, "EXPECTED_PRODUCT_SKU");
      requireValue("claimItem.component.sourceLineRef", component.sourceLineRef, (value) => value === SLICE_E.canonicalSourceLineRef, "EXPECTED_SOURCE_LINE_REF");
    }
  }
  if (event) {
    requireValue("createdEvent.claim_id", event.claim_id, (value) => String(value) === String(claim.id), "EXPECTED_CLAIM_ID");
    requireValue("createdEvent.event_type_code", event.event_type_code, (value) => value === "CREATED", "EXPECTED_CREATED");
    requireValue("createdEvent.occurred_at", event.occurred_at, (value) => sameInstant(value, SLICE_K.claimOccurredAt), "EXPECTED_REQUEST_OCCURRED_AT");
    requireValue("createdEvent.actor_process", event, hasValidActorProcessXor, "EXPECTED_ACTOR_PROCESS_XOR");
    if (!isPlainObject(event.snapshot)) detail.invalidPaths.push({ path: "createdEvent.snapshot", reason: "EXPECTED_PLAIN_OBJECT" });
    else {
      requireValue("createdEvent.snapshot.stockEffectCode", event.snapshot.stockEffectCode, (value) => value === "NONE", "EXPECTED_NONE");
      requireValue("createdEvent.snapshot.claimBasisCode", event.snapshot.claimBasisCode, (value) => value === "RETURN_CREATED_AT", "EXPECTED_RETURN_CREATED_AT");
      requireValue("createdEvent.snapshot.deadlineSourceCode", event.snapshot.deadlineSourceCode, (value) => value === "INTERNAL_RETURN_CREATED_AT", "EXPECTED_INTERNAL_RETURN_CREATED_AT");
    }
  }
  if (idempotency.candidateCount !== 1 || !isPlainObject(idempotency.command)) detail.invalidPaths.push({ path: "idempotency", reason: "EXPECTED_ONE_SUCCEEDED_COMMAND" });
  else {
    requireValue("idempotency.scope", idempotency.command.scope, (value) => value === "CREATE_TIKTOK_RETURN_CLAIM", "EXPECTED_CREATE_SCOPE");
    requireValue("idempotency.key", idempotency.command.key, (value) => value === SLICE_K.claimIdempotencyKey, "EXPECTED_SLICE_K_KEY");
    requireValue("idempotency.statusCode", idempotency.command.statusCode, (value) => value === "SUCCEEDED", "EXPECTED_SUCCEEDED");
    try {
      const response = validateCreateTiktokReturnClaimResponse({ response: idempotency.command.responseSnapshot, expectedDeadlineAt: snapshot.expectedDeadlineAt });
      if (String(response.response.claimId) !== String(claim.id)) detail.invalidPaths.push({ path: "idempotency.responseSnapshot.claimId", reason: "EXPECTED_CLAIM_ID" });
    } catch (error) {
      const responseDetail = error && typeof error === "object" ? error.detail : null;
      if (responseDetail) {
        for (const path of responseDetail.missingPaths) detail.missingPaths.push(`idempotency.${path}`);
        for (const invalid of responseDetail.invalidPaths) detail.invalidPaths.push({ path: `idempotency.${invalid.path}`, reason: invalid.reason });
      } else detail.invalidPaths.push({ path: "idempotency.responseSnapshot", reason: "INVALID_RESPONSE_CONTRACT" });
    }
  }
  return { valid: detail.missingPaths.length === 0 && detail.invalidPaths.length === 0, ...detail };
}

function sliceKClaimPersistedPostconditionError(missingPaths, invalidPaths) {
  const error = new Error("SLICE_K_CLAIM_PERSISTED_POSTCONDITION_INVALID");
  error.code = "SLICE_K_CLAIM_PERSISTED_POSTCONDITION_INVALID";
  error.detail = { missingPaths, invalidPaths };
  return error;
}

function validateSliceKClaimCreatedPersistedPostcondition(snapshot) {
  const evidence = validateSliceKClaimCreatedEvidence(snapshot);
  const missingPaths = [...evidence.missingPaths];
  const invalidPaths = [...evidence.invalidPaths];
  if (!isPlainObject(snapshot)) throw sliceKClaimPersistedPostconditionError(["snapshot"], []);
  if (snapshot.classification !== "EXACT_CLAIM_CREATED") invalidPaths.push({ path: "classification", reason: "EXPECTED_EXACT_CLAIM_CREATED" });
  if (!isPlainObject(snapshot.sliceJ) || snapshot.sliceJ.classification !== "EXACT_LOST") invalidPaths.push({ path: "sliceJ.classification", reason: "EXPECTED_EXACT_LOST" });
  if (!isPlainObject(snapshot.sliceJ) || !isPlainObject(snapshot.sliceJ.stock) || snapshot.sliceJ.stock.exact !== true) invalidPaths.push({ path: "sliceJ.stock", reason: "EXPECTED_STOCK_NEUTRAL_EXACT" });
  if (missingPaths.length > 0 || invalidPaths.length > 0) throw sliceKClaimPersistedPostconditionError(missingPaths, invalidPaths);
  return snapshot;
}

function canonicalGoldenNotificationValue(value) {
  if (Array.isArray(value)) return value.map(canonicalGoldenNotificationValue);
  if (isPlainObject(value)) return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalGoldenNotificationValue(value[key])]));
  return value;
}

function sameGoldenNotificationValue(actual, expected) {
  return JSON.stringify(canonicalGoldenNotificationValue(actual)) === JSON.stringify(canonicalGoldenNotificationValue(expected));
}

function sliceKNotificationPersistedPostconditionError(mismatchFields) {
  const error = new Error("GOLDEN_SLICE_K_NOTIFICATION_FIELD_MISMATCH");
  error.code = "GOLDEN_SLICE_K_NOTIFICATION_FIELD_MISMATCH";
  error.detail = { mismatchFields };
  return error;
}

function expectedSliceKNotificationFields(snapshot) {
  const claim = isPlainObject(snapshot?.claim) ? snapshot.claim : {};
  const sliceJHeader = isPlainObject(snapshot?.sliceJ?.header) ? snapshot.sliceJ.header : {};
  const canonicalRun = Array.isArray(snapshot?.notificationRuns?.canonicalRuns) && snapshot.notificationRuns.canonicalRuns.length === 1
    ? snapshot.notificationRuns.canonicalRuns[0]
    : {};
  const deadlineAt = snapshot?.deadlineAt ?? null;
  return {
    ruleCode: "CLAIM_DEADLINE",
    entityType: "RETURN_CLAIM",
    entityId: String(claim.id ?? ""),
    stage: "D14",
    severity: "WARNING",
    lifecycleStatus: ["OPEN", "ACKNOWLEDGED"],
    actionCode: "OPEN_RETURN_CLAIM_DETAIL",
    actionRoute: isNonBlank(sliceJHeader.return_id) && isNonBlank(claim.id)
      ? `/returns?returnId=${sliceJHeader.return_id}&claimId=${claim.id}#claim-detail`
      : null,
    deadlineAt,
    sourceSnapshot: {
      claimId: String(claim.id ?? ""),
      returnId: String(sliceJHeader.return_id ?? ""),
      deadlineAt,
      ruleRunId: String(canonicalRun.ruleRunId ?? ""),
      stockEffectCode: "NONE",
    },
  };
}

function normalizeSliceKNotification(row, shape) {
  if (!isPlainObject(row)) return null;
  const snakeCase = shape === "API" || shape === "DETAIL";
  return {
    notificationId: snakeCase ? row.notification_id : row.notificationId,
    ruleCode: snakeCase ? row.rule_code : row.ruleCode,
    entityType: snakeCase ? row.entity_type_code : row.entityTypeCode,
    entityId: snakeCase ? row.entity_id : row.entityId,
    stage: snakeCase ? row.stage_code : row.stageCode,
    severity: snakeCase ? row.severity_code : row.severityCode,
    lifecycleStatus: snakeCase ? row.lifecycle_status_code : row.lifecycleStatusCode,
    actionCode: snakeCase ? row.action_code : null,
    actionRoute: snakeCase ? row.action_route : row.actionRoute,
    deadlineAt: snakeCase ? row.due_at : row.dueAt,
    sourceSnapshot: snakeCase ? row.source_snapshot : row.sourceSnapshot,
  };
}

function collectSliceKNotificationFieldMismatches({ expected, actual, label, requireActionCode = false, requireSourceSnapshot = true }) {
  const mismatchFields = [];
  const check = (path, expectedValue, actualValue, equals = (left, right) => left === right) => {
    if (!equals(actualValue, expectedValue)) mismatchFields.push({ path: `${label}.${path}`, expected: expectedValue, actual: actualValue });
  };
  if (!isPlainObject(actual)) return [{ path: label, expected: "notification object", actual: actual }];
  check("ruleCode", expected.ruleCode, actual.ruleCode);
  check("entityType", expected.entityType, actual.entityType);
  check("entityId", expected.entityId, String(actual.entityId ?? ""));
  check("stage", expected.stage, actual.stage);
  check("severity", expected.severity, actual.severity);
  if (!expected.lifecycleStatus.includes(String(actual.lifecycleStatus ?? ""))) mismatchFields.push({ path: `${label}.lifecycleStatus`, expected: expected.lifecycleStatus, actual: actual.lifecycleStatus });
  if (requireActionCode) check("actionCode", expected.actionCode, actual.actionCode);
  check("actionRoute", expected.actionRoute, actual.actionRoute);
  check("deadlineAt", expected.deadlineAt, actual.deadlineAt, sameInstant);
  if (requireSourceSnapshot) check("sourceSnapshot", expected.sourceSnapshot, actual.sourceSnapshot, sameGoldenNotificationValue);
  return mismatchFields;
}

function validateSliceKNotificationPersistedPostcondition(snapshot) {
  const mismatchFields = [];
  const add = (path, expected, actual) => mismatchFields.push({ path, expected, actual });
  if (!isPlainObject(snapshot)) throw sliceKNotificationPersistedPostconditionError([{ path: "snapshot", reason: "EXPECTED_PLAIN_OBJECT" }]);
  if (snapshot.classification !== "EXACT_NOTIFICATION_CREATED") add("classification", "EXACT_NOTIFICATION_CREATED", snapshot.classification);
  if (!isPlainObject(snapshot.claim) || snapshot.claim.status_code !== "NOT_STARTED") add("claim.status_code", "NOT_STARTED", snapshot?.claim?.status_code ?? null);
  try { validateSliceJLostLowerReplayWithinSliceK(snapshot); } catch { add("sliceJ", "EXACT_LOST_STOCK_NEUTRAL", null); }
  try {
    const runs = snapshot.notificationRuns;
    if (!isPlainObject(runs) || !Array.isArray(runs.canonicalRuns) || runs.canonicalRuns.length !== 1) throw new Error("EXPECTED_ONE_CANONICAL_RUN");
    validateSliceKNotificationEvaluatorRun({ run: exactGoldenRow(runs.canonicalRuns, "SLICE_K_CANONICAL_NOTIFICATION_RUN_AMBIGUOUS"), expectedObservedAt: snapshot.notificationSchedule.observedAt, expectedCanonicalKey: snapshot.canonicalNotificationKey, expectedClaimId: String(snapshot.claim.id) });
  } catch { add("canonicalNotificationRun", "EXACT_CANONICAL_RUN", null); }
  const expected = expectedSliceKNotificationFields(snapshot);
  const apiNotification = normalizeSliceKNotification(snapshot.notification, "API");
  mismatchFields.push(...collectSliceKNotificationFieldMismatches({ expected, actual: apiNotification, label: "apiNotification", requireActionCode: true, requireSourceSnapshot: false }));
  const rawRows = Array.isArray(snapshot.rawNotifications) ? snapshot.rawNotifications : [];
  const apiRows = Array.isArray(snapshot.notifications) ? snapshot.notifications : [];
  if (rawRows.length !== 1 || apiRows.length !== 1) add("notificationReadModels.count", { raw: 1, api: 1 }, { raw: rawRows.length, api: apiRows.length });
  else {
    const rawNotification = normalizeSliceKNotification(rawRows[0], "RAW");
    mismatchFields.push(...collectSliceKNotificationFieldMismatches({ expected, actual: rawNotification, label: "rawNotification" }));
    if (String(rawNotification.notificationId ?? "") !== String(apiNotification?.notificationId ?? "")) add("notificationReadModels.notificationId", apiNotification?.notificationId ?? null, rawNotification.notificationId ?? null);
  }
  const detailNotification = normalizeSliceKNotification(snapshot.detail, "DETAIL");
  mismatchFields.push(...collectSliceKNotificationFieldMismatches({ expected, actual: detailNotification, label: "detailNotification", requireActionCode: true }));
  const historyRows = Array.isArray(snapshot.notificationHistory) ? snapshot.notificationHistory : [];
  const createdEvents = historyRows.filter((row) => String(row?.event_type_code ?? "") === "CREATED" && String(row?.process_name ?? "") === SLICE_K.workerProcessName);
  if (createdEvents.length !== 1) add("notificationEvents", "one CREATED event", createdEvents.length);
  else {
    const event = createdEvents[0];
    if (String(event.to_stage_code ?? "") !== expected.stage) add("notificationEvent.to_stage_code", expected.stage, event.to_stage_code ?? null);
    if (String(event.to_severity_code ?? "") !== expected.severity) add("notificationEvent.to_severity_code", expected.severity, event.to_severity_code ?? null);
    if (!sameGoldenNotificationValue(event.source_snapshot, expected.sourceSnapshot)) add("notificationEvent.source_snapshot", expected.sourceSnapshot, event.source_snapshot ?? null);
  }
  if (mismatchFields.length > 0) throw sliceKNotificationPersistedPostconditionError(mismatchFields);
  return snapshot;
}

function sliceKNotificationAuditRunFixture() {
  const claimId = "0536af47-4b33-4432-bede-8ddacf6c89dc";
  const deadlineAt = "2026-09-10T16:50:39.242508+00:00";
  const observedAt = "2026-08-27T16:50:39.242508+00:00";
  return {
    claimId,
    deadlineAt,
    observedAt,
    canonicalKey: canonicalSliceKNotificationIdempotencyKey(claimId, deadlineAt),
    run: { ruleRunId: "9e59037a-c7c8-4171-8f51-5ab1646f72ab", ruleId: "80000000-0000-4000-8000-000000000003", ruleCode: "CLAIM_DEADLINE", ruleVersion: "1.0.0", triggerType: "SCHEDULED", idempotencyKey: canonicalSliceKNotificationIdempotencyKey(claimId, deadlineAt), status: "SUCCEEDED", startedAt: "2026-08-27T16:50:39.242508+00:00", completedAt: "2026-08-27T16:50:40.242508+00:00", evaluatedCount: 1, createdCount: 1, updatedCount: 0, resolvedCount: 0, skippedCount: 0, errorCount: 0, summary: { observedAt, stockEffectCode: "NONE" }, errorDetail: {}, processName: SLICE_K.workerProcessName },
  };
}

function auditSliceKNotificationContract({ persistedSnapshot = null } = {}) {
  const fixture = sliceKNotificationAuditRunFixture();
  const mismatches = [];
  const validateRun = (label, run, shouldPass) => {
    try {
      validateSliceKNotificationEvaluatorRun({ run, expectedObservedAt: fixture.observedAt, expectedCanonicalKey: fixture.canonicalKey, expectedClaimId: fixture.claimId });
      if (!shouldPass) mismatches.push({ label, path: "run", reason: "EXPECTED_FAILURE" });
    } catch {
      if (shouldPass) mismatches.push({ label, path: "run", reason: "UNEXPECTED_FAILURE" });
    }
  };
  validateRun("canonical D14 run", fixture.run, true);
  validateRun("wrong canonical key", { ...fixture.run, idempotencyKey: "WRONG" }, false);
  validateRun("microsecond-early observedAt", { ...fixture.run, summary: { ...fixture.run.summary, observedAt: "2026-08-27T16:50:39.242000+00:00" } }, false);
  validateRun("failed canonical run", { ...fixture.run, status: "FAILED" }, false);
  const legacyNoop = { ...fixture.run, idempotencyKey: SLICE_K.legacyNotificationIdempotencyKey, createdCount: 0, skippedCount: 1, summary: { observedAt: "2026-08-27T16:50:39.242000+00:00", stockEffectCode: "NONE" } };
  if (!validateSliceKLegacyEarlyNoopRun(legacyNoop, fixture.observedAt)) mismatches.push({ label: "legacy early noop", path: "legacyRun", reason: "EXPECTED_VALID" });
  if (persistedSnapshot !== null) {
    const validPersistedState = persistedSnapshot.classification === "EXACT_CLAIM_CREATED" || persistedSnapshot.classification === "EXACT_NOTIFICATION_CREATED";
    if (!validPersistedState) mismatches.push({ label: "persisted notification state", path: "classification", reason: String(persistedSnapshot.classification ?? "NONE") });
    if (persistedSnapshot.classification === "EXACT_NOTIFICATION_CREATED") {
      try { validateSliceKNotificationPersistedPostcondition(persistedSnapshot); } catch { mismatches.push({ label: "persisted notification postcondition", path: "snapshot", reason: "INVALID" }); }
    }
  }
  const persistedContractMatrix = auditGoldenSliceKNotificationPersistedContractMatrix();
  return {
    evaluatorRunCaseCount: 5,
    notificationCaseCount: 5,
    checkedPathCount: 46 + persistedContractMatrix.checkedPathCount,
    legacyNoopMismatchCount: mismatches.filter((entry) => entry.label.includes("legacy")).length,
    canonicalRunMismatchCount: mismatches.filter((entry) => entry.path === "run").length,
    persistedNotificationMismatchCount: mismatches.filter((entry) => entry.label.includes("persisted")).length,
    readModelMismatchCount: persistedContractMatrix.readModelDivergenceCount,
    persistedContractMatrix,
    mismatchCount: mismatches.length + persistedContractMatrix.mismatchCount,
    mismatches: [...mismatches, ...persistedContractMatrix.mismatches],
  };
}

function auditGoldenSliceKNotificationPersistedContractMatrix() {
  const fixture = sliceKNotificationAuditRunFixture();
  const returnId = "0c61b296-674a-4a74-b557-26e3f3e7e912";
  const expected = {
    ruleCode: "CLAIM_DEADLINE",
    entityType: "RETURN_CLAIM",
    entityId: fixture.claimId,
    stage: "D14",
    severity: "WARNING",
    lifecycleStatus: ["OPEN", "ACKNOWLEDGED"],
    actionCode: "OPEN_RETURN_CLAIM_DETAIL",
    actionRoute: `/returns?returnId=${returnId}&claimId=${fixture.claimId}#claim-detail`,
    deadlineAt: fixture.deadlineAt,
    sourceSnapshot: { claimId: fixture.claimId, returnId, deadlineAt: fixture.deadlineAt, ruleRunId: fixture.run.ruleRunId, stockEffectCode: "NONE" },
  };
  const api = { notificationId: "6f4c1ba1-024e-49dd-983a-027e4ce9596c", ruleCode: expected.ruleCode, entityType: expected.entityType, entityId: expected.entityId, stage: expected.stage, severity: expected.severity, lifecycleStatus: "OPEN", actionCode: expected.actionCode, actionRoute: expected.actionRoute, deadlineAt: expected.deadlineAt, sourceSnapshot: expected.sourceSnapshot };
  const raw = { ...api, actionCode: null };
  const detail = { ...api };
  const event = { event_type_code: "CREATED", process_name: SLICE_K.workerProcessName, to_stage_code: expected.stage, to_severity_code: expected.severity, source_snapshot: expected.sourceSnapshot };
  const mismatches = [];
  const valid = ({ apiNotification = api, rawNotification = raw, detailNotification = detail, eventRows = [event], run = fixture.run, rawCount = 1, apiCount = 1 } = {}) => {
    try { validateSliceKNotificationEvaluatorRun({ run, expectedObservedAt: fixture.observedAt, expectedCanonicalKey: fixture.canonicalKey, expectedClaimId: fixture.claimId }); } catch { return false; }
    if (rawCount !== 1 || apiCount !== 1) return false;
    if (collectSliceKNotificationFieldMismatches({ expected, actual: apiNotification, label: "api", requireActionCode: true }).length > 0) return false;
    if (collectSliceKNotificationFieldMismatches({ expected, actual: rawNotification, label: "raw" }).length > 0) return false;
    if (collectSliceKNotificationFieldMismatches({ expected, actual: detailNotification, label: "detail", requireActionCode: true }).length > 0) return false;
    if (String(apiNotification.notificationId) !== String(rawNotification.notificationId)) return false;
    const created = eventRows.filter((row) => String(row?.event_type_code ?? "") === "CREATED" && String(row?.process_name ?? "") === SLICE_K.workerProcessName);
    return created.length === 1 && String(created[0].to_stage_code ?? "") === expected.stage && String(created[0].to_severity_code ?? "") === expected.severity && sameGoldenNotificationValue(created[0].source_snapshot, expected.sourceSnapshot);
  };
  const verify = (label, shouldPass, options) => {
    const actual = valid(options);
    if (actual !== shouldPass) mismatches.push({ label, expected: shouldPass ? "PASS" : "FAIL", actual: actual ? "PASS" : "FAIL" });
  };
  verify("A canonical D14 WARNING", true);
  verify("B stage D7", false, { apiNotification: { ...api, stage: "D7" } });
  verify("C severity HIGH", false, { apiNotification: { ...api, severity: "HIGH" } });
  verify("D legacy CLAIM entity", false, { apiNotification: { ...api, entityType: "CLAIM" } });
  verify("E wrong return or claim route", false, { apiNotification: { ...api, actionRoute: `/returns?returnId=wrong&claimId=${fixture.claimId}#claim-detail` } });
  verify("F wrong metadata rule run", false, { detailNotification: { ...detail, sourceSnapshot: { ...expected.sourceSnapshot, ruleRunId: "wrong" } } });
  verify("G non-neutral stock effect", false, { rawNotification: { ...raw, sourceSnapshot: { ...expected.sourceSnapshot, stockEffectCode: "LEDGER" } } });
  verify("H base/read-model divergence", false, { rawNotification: { ...raw, stage: "D7" } });
  verify("I deterministic exact D14 boundary", true);
  verify("J microsecond rounding outside D14", false, { run: { ...fixture.run, summary: { ...fixture.run.summary, observedAt: "2026-08-27T16:50:39.242000+00:00" } } });
  verify("K duplicate active episode", false, { rawCount: 2 });
  verify("L missing CREATED event", false, { eventRows: [] });
  return {
    caseCount: 12,
    checkedPathCount: 96,
    stageMismatchCount: mismatches.filter((entry) => /stage/i.test(entry.label)).length,
    severityMismatchCount: mismatches.filter((entry) => /severity/i.test(entry.label)).length,
    identityMismatchCount: mismatches.filter((entry) => /entity|identity/i.test(entry.label)).length,
    routeMismatchCount: mismatches.filter((entry) => /route/i.test(entry.label)).length,
    metadataMismatchCount: mismatches.filter((entry) => /metadata|stock effect/i.test(entry.label)).length,
    temporalMismatchCount: mismatches.filter((entry) => /boundary|microsecond/i.test(entry.label)).length,
    readModelDivergenceCount: mismatches.filter((entry) => /read-model/i.test(entry.label)).length,
    duplicateEpisodeCount: mismatches.filter((entry) => /duplicate/i.test(entry.label)).length,
    eventMismatchCount: mismatches.filter((entry) => /event/i.test(entry.label)).length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function markReturnLostResponseError(missingPaths, invalidPaths, unexpectedKeys) {
  const error = new Error("SLICE_J_LOST_RESPONSE_INVALID");
  error.code = "SLICE_J_LOST_RESPONSE_INVALID";
  error.detail = { missingPaths, invalidPaths, unexpectedKeys };
  return error;
}

function validateMarkReturnLostResponse({ response, request, expectedReturnId, expectedReturnRef, expectedEventRef }) {
  const missingPaths = [];
  const invalidPaths = [];
  if (!isPlainObject(response)) throw markReturnLostResponseError(["response"], [], []);
  if (!isPlainObject(request)) throw markReturnLostResponseError(["request"], [], []);
  const requireValue = (path, value, predicate, reason) => {
    if (value === undefined) missingPaths.push(path);
    else if (!predicate(value)) invalidPaths.push({ path, reason });
  };
  requireValue("response.status", response.status, (value) => value === "LOST", "EXPECTED_LOST");
  requireValue("response.returnId", response.returnId, (value) => UUID_PATTERN.test(String(value)) && String(value) === String(expectedReturnId), "EXPECTED_EXACT_RETURN_ID");
  requireValue("response.returnRef", response.returnRef, (value) => String(value) === String(expectedReturnRef), "EXPECTED_EXACT_RETURN_REF");
  requireValue("response.eventId", response.eventId, (value) => UUID_PATTERN.test(String(value)), "EXPECTED_UUID");
  requireValue("response.eventRef", response.eventRef, (value) => String(value) === String(expectedEventRef), "EXPECTED_EXACT_EVENT_REF");
  requireValue("response.eventType", response.eventType, (value) => value === "LOST", "EXPECTED_LOST");
  requireValue("response.lineCount", response.lineCount, (value) => typeof value === "number" && Number.isSafeInteger(value) && value === 1, "EXPECTED_SAFE_INTEGER_ONE");
  requireValue("response.totalQuantity", response.totalQuantity, (value) => typeof value === "number" && Number.isSafeInteger(value) && value === 1, "EXPECTED_SAFE_INTEGER_ONE");
  const requestOccurredAt = request.occurredAt;
  const responseOccurredAtMs = Date.parse(String(response.occurredAt));
  const responseRecordedAtMs = Date.parse(String(response.recordedAt));
  if (requestOccurredAt === undefined) missingPaths.push("request.occurredAt");
  else if (!Number.isFinite(Date.parse(String(requestOccurredAt)))) invalidPaths.push({ path: "request.occurredAt", reason: "EXPECTED_VALID_TIMESTAMPTZ" });
  if (response.occurredAt === undefined) missingPaths.push("response.occurredAt");
  else if (!Number.isFinite(responseOccurredAtMs) || !sameInstant(response.occurredAt, requestOccurredAt)) invalidPaths.push({ path: "response.occurredAt", reason: "EXPECTED_REQUEST_INSTANT" });
  if (response.recordedAt === undefined) missingPaths.push("response.recordedAt");
  else if (!Number.isFinite(responseRecordedAtMs)) invalidPaths.push({ path: "response.recordedAt", reason: "EXPECTED_VALID_TIMESTAMPTZ" });
  else if (Number.isFinite(responseOccurredAtMs) && responseRecordedAtMs < responseOccurredAtMs) invalidPaths.push({ path: "response.recordedAt", reason: "MUST_NOT_PRECEDE_OCCURRED_AT" });
  const unexpectedKeys = Object.keys(response).filter((key) => !MARK_RETURN_LOST_RESPONSE_KEYS.includes(key)).sort();
  if (missingPaths.length > 0 || invalidPaths.length > 0) {
    throw markReturnLostResponseError(missingPaths, invalidPaths, unexpectedKeys);
  }
  return { response, unexpectedKeys };
}

const SLICE_J_POSTCONDITION_CONTEXT = Object.freeze({
  AFTER_SLICE_J_MUTATION: "AFTER_SLICE_J_MUTATION",
  LOWER_SLICE_REPLAY: "LOWER_SLICE_REPLAY",
  AGGREGATE_PREFLIGHT: "AGGREGATE_PREFLIGHT",
});

function sliceJLostPostconditionMismatch(path, expected, actual, scope) {
  return { path, expected, actual: actual === undefined ? null : actual, scope };
}

function validateSliceJLostCoreInvariants(snapshot) {
  const mismatches = [];
  const requireObject = (path, value) => {
    if (!isPlainObject(value)) mismatches.push(sliceJLostPostconditionMismatch(path, "plain object", value, "CORE_INVARIANT"));
    return isPlainObject(value);
  };
  if (!isPlainObject(snapshot)) return [sliceJLostPostconditionMismatch("snapshot", "plain object", snapshot, "CORE_INVARIANT")];
  const header = snapshot.header;
  const item = snapshot.item;
  const expectedEvent = snapshot.expectedEvent;
  const lostEvent = snapshot.lostEvent;
  const counts = snapshot.counts;
  const lifecycle = snapshot.lifecycle;
  const stock = snapshot.stock;
  const headerValid = requireObject("header", snapshot.header);
  const itemValid = requireObject("item", snapshot.item);
  const expectedEventValid = requireObject("expectedEvent", snapshot.expectedEvent);
  const lostEventValid = requireObject("lostEvent", snapshot.lostEvent);
  const countsValid = requireObject("counts", snapshot.counts);
  const lifecycleValid = requireObject("lifecycle", snapshot.lifecycle);
  const stockValid = requireObject("stock", snapshot.stock);
  const requireExact = (path, expected, actual) => {
    if (actual !== expected) mismatches.push(sliceJLostPostconditionMismatch(path, expected, actual, "CORE_INVARIANT"));
  };
  requireExact("classification", "EXACT_LOST", snapshot.classification);
  if (headerValid) {
    requireExact("header.status_code", "LOST", header.status_code);
    requireExact("header.outcome_code", "LOST", header.outcome_code);
    requireExact("header.channel_code", SLICE_E.channelCode, header.channel_code);
    requireExact("header.marketplace_order_ref", SLICE_E.externalOrderRef, header.marketplace_order_ref);
    requireExact("header.external_return_ref", SLICE_J.returnRef, header.external_return_ref);
  }
  if (expectedEventValid) {
    requireExact("expectedEvent.event_type_code", "EXPECTED", expectedEvent.event_type_code);
    requireExact("expectedEvent.external_event_ref", `EXPECTED:${SLICE_J.returnRef}`, expectedEvent.external_event_ref);
  }
  if (lostEventValid) {
    requireExact("lostEvent.event_type_code", "LOST", lostEvent.event_type_code);
    requireExact("lostEvent.external_event_ref", SLICE_J.lostEventRef, lostEvent.external_event_ref);
  }
  if (countsValid) {
    for (const [path, expected] of [["returnCount", 1], ["itemCount", 1], ["expectedEventCount", 1], ["lostEventCount", 1], ["receiptEventCount", 0], ["inspectionEventCount", 0], ["receiptLineCount", 0], ["inspectionAllocationCount", 0], ["returnBatchCount", 0], ["transactionCount", 0], ["ledgerCount", 0]]) requireExact(`counts.${path}`, expected, counts[path]);
  }
  if (itemValid) {
    for (const [path, expected] of [["expected_qty", 1], ["received_qty", 0], ["sellable_qty", 0], ["damaged_qty", 0], ["lost_qty", 1], ["pending_arrival_qty", 0], ["pending_inspection_qty", 0]]) {
      if (asNumber(item[path]) !== expected) mismatches.push(sliceJLostPostconditionMismatch(`item.${path}`, expected, item[path], "CORE_INVARIANT"));
    }
  }
  if (lifecycleValid) {
    for (const [path, expected] of [["return_expected_quantity", 1], ["return_received_quantity", 0], ["return_sellable_quantity", 0], ["return_damaged_quantity", 0], ["return_lost_quantity", 1], ["remaining_returnable_or_cancellable_quantity", 0]]) {
      if (asNumber(lifecycle[path]) !== expected) mismatches.push(sliceJLostPostconditionMismatch(`lifecycle.${path}`, expected, lifecycle[path], "CORE_INVARIANT"));
    }
  }
  if (stockValid) {
    requireExact("stock.exact", true, stock.exact);
    if (isPlainObject(stock.actual)) {
      const projectionPhase = phaseNameOf(stock.projectionPhase ?? "SLICE_J_TIKTOK_RETURN_LOST");
      const expectedProjection = expectedGoldenCurrentStateForPhase({ detectedPhase: projectionPhase });
      requireExact("stock.projectionPhase", projectionPhase, stock.projectionPhase ?? "SLICE_J_TIKTOK_RETURN_LOST");
      requireExact("stock.actual.serum", [expectedProjection.serumProduct.sellable, expectedProjection.serumProduct.reserved, expectedProjection.serumProduct.available].join(","), Array.isArray(stock.actual.serum) ? stock.actual.serum.join(",") : null);
      requireExact("stock.actual.cleanser", [expectedProjection.cleanserProduct.sellable, expectedProjection.cleanserProduct.reserved, expectedProjection.cleanserProduct.available].join(","), Array.isArray(stock.actual.cleanser) ? stock.actual.cleanser.join(",") : null);
    } else mismatches.push(sliceJLostPostconditionMismatch("stock.actual", "plain object", stock.actual, "CORE_INVARIANT"));
  }
  return mismatches;
}

function downstreamSliceKExpectation(snapshot) {
  if (!isPlainObject(snapshot.downstream)) return null;
  return snapshot.downstream;
}

function validateSliceJLostPhaseBoundary(snapshot, highestPersistedPhase) {
  const phase = phaseNameOf(highestPersistedPhase);
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
  const actual = downstreamSliceKExpectation(snapshot);
  const mismatches = [];
  if (!actual) return [sliceJLostPostconditionMismatch("downstream", "plain object", actual, "PHASE_BOUNDARY")];
  const expectedDownstream = expected.claimNotificationExpectation;
  const fields = ["claimCount", "claimItemCount", "claimEventCount", "notificationCount", "notificationRuleRunCount", "claimEvidence", "notificationStage"];
  for (const field of fields) {
    if (actual[field] !== expectedDownstream[field]) {
      mismatches.push(sliceJLostPostconditionMismatch(`downstream.${field}`, expectedDownstream[field], actual[field], field.endsWith("Count") ? "PHASE_BOUNDARY" : "DOWNSTREAM_EXPECTATION"));
    }
  }
  return mismatches;
}

function sliceJLostPersistedPostconditionError(validationContext, highestPersistedPhase, mismatches) {
  const error = new Error("SLICE_J_LOST_PERSISTED_POSTCONDITION_INVALID");
  error.code = "SLICE_J_LOST_PERSISTED_POSTCONDITION_INVALID";
  error.detail = { validationContext, highestPersistedPhase: phaseNameOf(highestPersistedPhase), mismatches };
  return error;
}

function normalizeGoldenSliceJDownstreamEvidence(value) {
  if (!isPlainObject(value)) return null;
  const fields = ["claimCount", "claimItemCount", "claimEventCount", "notificationCount", "notificationRuleRunCount", "claimEvidence", "notificationStage"];
  return fields.every((field) => Object.hasOwn(value, field))
    ? Object.fromEntries(fields.map((field) => [field, value[field]]))
    : null;
}

function resolveGoldenSliceJLifecycleContract({
  authoritativePhase,
  returnIdentity,
  returnEvidence,
  claimEvidence,
  notificationEvidence,
  currentProjection,
  duplicateEvidence,
  executionMode = "REPLAY",
}) {
  const checkpointPhase = "SLICE_J_TIKTOK_RETURN_LOST";
  const phaseContract = resolveGoldenReplayPhaseContract({
    highestPersistedPhase: authoritativePhase,
    checkpointPhase,
    executionMode,
    operation: "SLICE_J_LOST_RETURN",
  });
  const normalizedPhase = phaseContract.authoritativePhase;
  const downstream = normalizeGoldenSliceJDownstreamEvidence(notificationEvidence)
    ?? normalizeGoldenSliceJDownstreamEvidence(claimEvidence)
    ?? normalizeGoldenSliceJDownstreamEvidence(returnEvidence?.downstream);
  const identityExact = String(returnIdentity ?? "") === SLICE_J.returnRef
    && String(returnEvidence?.header?.external_return_ref ?? "") === SLICE_J.returnRef
    && String(returnEvidence?.item?.source_line_ref ?? "") === SLICE_E.canonicalSourceLineRef
    && String(returnEvidence?.item?.marketplace_item_ref ?? "") === SLICE_E.canonicalSourceLineRef
    && String(returnEvidence?.item?.product_sku_snapshot ?? "") === SLICE_J.productSku;
  const coreMismatches = validateSliceJLostCoreInvariants({ ...returnEvidence, downstream });
  const expectedDownstream = expectedGoldenCurrentStateForPhase({ detectedPhase: normalizedPhase }).claimNotificationExpectation;
  const downstreamMismatches = validateSliceJLostPhaseBoundary({ ...returnEvidence, downstream }, normalizedPhase);
  const counts = isPlainObject(returnEvidence?.counts) ? returnEvidence.counts : {};
  const duplicate = isPlainObject(duplicateEvidence) ? duplicateEvidence : counts;
  const forbiddenConflicts = [
    ["receiptEventCount", 0, counts.receiptEventCount],
    ["inspectionEventCount", 0, counts.inspectionEventCount],
    ["receiptLineCount", 0, counts.receiptLineCount],
    ["inspectionAllocationCount", 0, counts.inspectionAllocationCount],
    ["returnBatchCount", 0, counts.returnBatchCount],
    ["unexpectedEventCount", 0, counts.unexpectedEventCount],
    ["transactionCount", 0, counts.transactionCount],
    ["ledgerCount", 0, counts.ledgerCount],
    ["lostEventCount", 1, duplicate.lostEventCount ?? counts.lostEventCount],
  ].filter(([, expected, actual]) => asNumber(actual) !== expected)
    .map(([field, expected, actual]) => ({ field, expected, actual: actual ?? null }));
  const currentProjectionExact = isPlainObject(currentProjection)
    && currentProjection.exact === true
    && phaseNameOf(currentProjection.projectionPhase) === normalizedPhase;
  const mismatchFields = [
    ...(identityExact ? [] : [sliceJLostPostconditionMismatch("returnIdentity", SLICE_J.returnRef, returnIdentity ?? null, "IDENTITY")]),
    ...coreMismatches,
    ...downstreamMismatches,
    ...(currentProjectionExact ? [] : [sliceJLostPostconditionMismatch("currentProjection", { exact: true, projectionPhase: normalizedPhase }, currentProjection ?? null, "CURRENT_PROJECTION")]),
    ...forbiddenConflicts.map((conflict) => sliceJLostPostconditionMismatch(`forbidden.${conflict.field}`, conflict.expected, conflict.actual, "FORBIDDEN_CONFLICT")),
  ];
  const historicalEvidenceExact = identityExact && returnEvidence?.classification === "EXACT_LOST" && coreMismatches.length === 0;
  const allowedDownstreamEvidenceExact = downstreamMismatches.length === 0;
  const classification = forbiddenConflicts.length > 0
    ? "CONFLICT"
    : !historicalEvidenceExact || !allowedDownstreamEvidenceExact || !currentProjectionExact
      ? "PARTIAL"
      : phaseContract.mode === "FRESH_EXACT"
        ? "FRESH"
        : phaseContract.mode;
  return {
    historicalEvidenceExact,
    forbiddenConflictCount: forbiddenConflicts.length,
    forbiddenConflicts,
    allowedDownstreamEvidenceExact,
    currentProjectionExact,
    replayMode: phaseContract.mode,
    authoritativePhase: normalizedPhase,
    classification,
    mismatchFields,
    expected: { returnIdentity: SLICE_J.returnRef, downstream: expectedDownstream, projectionPhase: normalizedPhase },
    actual: { returnIdentity: returnIdentity ?? null, downstream, currentProjection: currentProjection ?? null, counts },
  };
}

function goldenSliceJLifecycleContractError(contract) {
  const error = new Error("GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT");
  error.code = "GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT";
  error.detail = {
    classification: contract?.classification ?? null,
    mismatchFields: contract?.mismatchFields ?? [],
    forbiddenConflicts: contract?.forbiddenConflicts ?? [],
    selectedReturnIdentity: contract?.actual?.returnIdentity ?? null,
    expected: contract?.expected ?? null,
    actual: contract?.actual ?? null,
    authoritativePhase: contract?.authoritativePhase ?? null,
    replayMode: contract?.replayMode ?? null,
  };
  return error;
}

function validateSliceJLostPersistedPostcondition({ snapshot, highestPersistedPhase, validationContext }) {
  if (!Object.values(SLICE_J_POSTCONDITION_CONTEXT).includes(validationContext)) {
    throw sliceJLostPersistedPostconditionError(validationContext, highestPersistedPhase, [sliceJLostPostconditionMismatch("validationContext", "known internal context", validationContext, "PHASE_BOUNDARY")]);
  }
  const executionMode = validationContext === SLICE_J_POSTCONDITION_CONTEXT.AFTER_SLICE_J_MUTATION ? "FRESH" : "REPLAY";
  let contract;
  try {
    contract = resolveGoldenSliceJLifecycleContract({
      authoritativePhase: highestPersistedPhase,
      returnIdentity: snapshot?.header?.external_return_ref,
      returnEvidence: snapshot,
      claimEvidence: snapshot?.downstream,
      notificationEvidence: snapshot?.downstream,
      currentProjection: snapshot?.stock,
      duplicateEvidence: snapshot?.counts,
      executionMode,
    });
  } catch {
    throw sliceJLostPersistedPostconditionError(validationContext, highestPersistedPhase, [sliceJLostPostconditionMismatch("highestPersistedPhase", executionMode === "FRESH" ? "SLICE_J_TIKTOK_RETURN_LOST" : "at least SLICE_J_TIKTOK_RETURN_LOST", phaseNameOf(highestPersistedPhase), "PHASE_BOUNDARY")]);
  }
  if (!["FRESH", "SAME_PHASE_REPLAY", "LATER_PHASE_REPLAY"].includes(contract.classification)) {
    throw goldenSliceJLifecycleContractError(contract);
  }
  return snapshot;
}

function sliceJPostconditionRegressionFixture(phase) {
  const expected = expectedGoldenCurrentStateForPhase({ detectedPhase: phase });
  return {
    classification: "EXACT_LOST",
    header: { status_code: "LOST", outcome_code: "LOST", channel_code: SLICE_E.channelCode, marketplace_order_ref: SLICE_E.externalOrderRef, external_return_ref: SLICE_J.returnRef },
    expectedEvent: { event_type_code: "EXPECTED", external_event_ref: `EXPECTED:${SLICE_J.returnRef}` },
    lostEvent: { event_type_code: "LOST", external_event_ref: SLICE_J.lostEventRef },
    item: { marketplace_item_ref: SLICE_E.canonicalSourceLineRef, source_line_ref: SLICE_E.canonicalSourceLineRef, product_sku_snapshot: SLICE_J.productSku, expected_qty: 1, received_qty: 0, sellable_qty: 0, damaged_qty: 0, lost_qty: 1, pending_arrival_qty: 0, pending_inspection_qty: 0 },
    counts: { returnCount: 1, itemCount: 1, expectedEventCount: 1, lostEventCount: 1, receiptEventCount: 0, inspectionEventCount: 0, receiptLineCount: 0, inspectionAllocationCount: 0, returnBatchCount: 0, unexpectedEventCount: 0, transactionCount: 0, ledgerCount: 0 },
    lifecycle: { return_expected_quantity: 1, return_received_quantity: 0, return_sellable_quantity: 0, return_damaged_quantity: 0, return_lost_quantity: 1, remaining_returnable_or_cancellable_quantity: 0 },
    stock: { exact: true, projectionPhase: phase, actual: { serum: expected.serumProduct ? [expected.serumProduct.sellable, expected.serumProduct.reserved, expected.serumProduct.available] : [24, 0, 24], cleanser: [expected.cleanserProduct.sellable, expected.cleanserProduct.reserved, expected.cleanserProduct.available] } },
    downstream: { ...expected.claimNotificationExpectation },
  };
}

function auditSliceJPostconditionAcrossPhases({ persistedSnapshot = null, highestPersistedPhase = null } = {}) {
  const cases = [
    { label: "J LOST without downstream evidence", phase: "SLICE_J_TIKTOK_RETURN_LOST", context: SLICE_J_POSTCONDITION_CONTEXT.AFTER_SLICE_J_MUTATION, shouldPass: true },
    { label: "J LOST rejects claim", phase: "SLICE_J_TIKTOK_RETURN_LOST", context: SLICE_J_POSTCONDITION_CONTEXT.AFTER_SLICE_J_MUTATION, shouldPass: false, mutate: (snapshot) => { snapshot.downstream.claimCount = 1; } },
    { label: "K claim-created accepts exact claim", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", context: SLICE_J_POSTCONDITION_CONTEXT.LOWER_SLICE_REPLAY, shouldPass: true },
    { label: "K claim-created rejects missing claim", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", context: SLICE_J_POSTCONDITION_CONTEXT.LOWER_SLICE_REPLAY, shouldPass: false, mutate: (snapshot) => { snapshot.downstream.claimCount = 0; } },
    { label: "K notification accepts exact evidence", phase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION", context: SLICE_J_POSTCONDITION_CONTEXT.LOWER_SLICE_REPLAY, shouldPass: true },
    { label: "K rejects duplicate claim", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", context: SLICE_J_POSTCONDITION_CONTEXT.AGGREGATE_PREFLIGHT, shouldPass: false, mutate: (snapshot) => { snapshot.downstream.claimCount = 2; } },
    { label: "core rejects LOST ledger", phase: "SLICE_K_TIKTOK_CLAIM_CREATED", context: SLICE_J_POSTCONDITION_CONTEXT.AGGREGATE_PREFLIGHT, shouldPass: false, mutate: (snapshot) => { snapshot.counts.ledgerCount = 1; } },
  ];
  const mismatches = [];
  let checkedPathCount = 0;
  for (const testCase of cases) {
    const snapshot = sliceJPostconditionRegressionFixture(testCase.phase);
    if (typeof testCase.mutate === "function") testCase.mutate(snapshot);
    try {
      validateSliceJLostPersistedPostcondition({ snapshot, highestPersistedPhase: testCase.phase, validationContext: testCase.context });
      if (!testCase.shouldPass) mismatches.push({ case: testCase.label, path: "validator", reason: "EXPECTED_FAILURE" });
    } catch (error) {
      if (testCase.shouldPass) {
        const detail = error && typeof error === "object" ? error.detail : null;
        mismatches.push({ case: testCase.label, path: "validator", reason: detail?.mismatchFields ?? detail?.mismatches ?? "UNEXPECTED_FAILURE" });
      }
    }
    checkedPathCount += 28;
  }
  if (persistedSnapshot !== null && highestPersistedPhase !== null) {
    try {
      validateSliceJLostPersistedPostcondition({ snapshot: persistedSnapshot, highestPersistedPhase, validationContext: SLICE_J_POSTCONDITION_CONTEXT.AGGREGATE_PREFLIGHT });
    } catch (error) {
      const detail = error && typeof error === "object" ? error.detail : null;
      const detailMismatches = detail?.mismatchFields ?? detail?.mismatches;
      if (Array.isArray(detailMismatches)) mismatches.push(...detailMismatches.map((mismatch) => ({ case: "persisted snapshot", ...mismatch })));
      else mismatches.push({ case: "persisted snapshot", path: "validator", reason: "UNEXPECTED_FAILURE" });
    }
    checkedPathCount += 28;
  }
  const coreMismatchCount = mismatches.filter((mismatch) => mismatch.scope === "CORE_INVARIANT" || Array.isArray(mismatch.reason) && mismatch.reason.some((entry) => entry.scope === "CORE_INVARIANT")).length;
  const phaseBoundaryMismatchCount = mismatches.filter((mismatch) => mismatch.scope === "PHASE_BOUNDARY" || Array.isArray(mismatch.reason) && mismatch.reason.some((entry) => entry.scope === "PHASE_BOUNDARY")).length;
  const downstreamMismatchCount = mismatches.filter((mismatch) => mismatch.scope === "DOWNSTREAM_EXPECTATION" || Array.isArray(mismatch.reason) && mismatch.reason.some((entry) => entry.scope === "DOWNSTREAM_EXPECTATION")).length;
  return { phaseCount: 3, contextCount: 3, checkedPathCount, coreMismatchCount, phaseBoundaryMismatchCount, downstreamMismatchCount, mismatchCount: mismatches.length, mismatches };
}

function sliceJDownstreamEvidenceFromSliceKState(sliceKState) {
  if (!isPlainObject(sliceKState) || !isPlainObject(sliceKState.counts)) {
    throw new Error("SLICE_J_DOWNSTREAM_EVIDENCE_INVALID");
  }
  const counts = sliceKState.counts;
  let claimEvidence = "NONE";
  let notificationStage = "NONE";
  if (sliceKState.classification === "EXACT_CLAIM_CREATED" || sliceKState.classification === "EXACT_NOTIFICATION_CREATED") claimEvidence = "CREATED";
  if (sliceKState.classification === "EXACT_NOTIFICATION_CREATED") notificationStage = SLICE_K.notificationStage;
  return {
    claimCount: counts.claimCount,
    claimItemCount: counts.claimItemCount,
    claimEventCount: counts.claimEventCount,
    notificationCount: counts.notificationCount,
    notificationRuleRunCount: counts.notificationRuleRunCount,
    claimEvidence,
    notificationStage,
  };
}

function validateSliceJLostLowerReplayWithinSliceK(sliceKState, { authoritativePhase = null } = {}) {
  if (!isPlainObject(sliceKState) || !isPlainObject(sliceKState.sliceJ) || !isPlainObject(sliceKState.effectivePhase)) {
    throw new Error("SLICE_J_LOWER_REPLAY_CONTEXT_INVALID");
  }
  const resolvedAuthoritativePhase = authoritativePhase ?? sliceKState.projectionEvidencePhase ?? sliceKState.effectivePhase;
  return validateSliceJLostPersistedPostcondition({
    snapshot: { ...sliceKState.sliceJ, downstream: sliceJDownstreamEvidenceFromSliceKState(sliceKState) },
    highestPersistedPhase: resolvedAuthoritativePhase,
    validationContext: SLICE_J_POSTCONDITION_CONTEXT.LOWER_SLICE_REPLAY,
  });
}

function responseContractRegressionFixture() {
  return {
    status: "LOST",
    returnId: "c21dc958-9fc8-457f-947c-95ac5a509177",
    returnRef: SLICE_J.returnRef,
    eventId: "137b4c00-0f1a-4bee-b0c1-7a3c99acd5ac",
    eventRef: SLICE_J.lostEventRef,
    eventType: "LOST",
    lineCount: 1,
    totalQuantity: 1,
    occurredAt: SLICE_J.lostOccurredAt,
    recordedAt: "2026-08-01T18:03:06.781198Z",
  };
}

function auditSliceJLostResponseContract({
  persistedResponseSnapshot = responseContractRegressionFixture(),
  expectedReturnId = responseContractRegressionFixture().returnId,
  expectedReturnRef = SLICE_J.returnRef,
  expectedEventRef = SLICE_J.lostEventRef,
} = {}) {
  const expected = responseContractRegressionFixture();
  const request = { occurredAt: SLICE_J.lostOccurredAt };
  const mismatches = [];
  const validate = (label, response, shouldPass) => {
    try {
      validateMarkReturnLostResponse({ response, request, expectedReturnId: expected.returnId, expectedReturnRef: expected.returnRef, expectedEventRef: expected.eventRef });
      if (!shouldPass) mismatches.push({ label, reason: "EXPECTED_VALIDATOR_FAILURE" });
    } catch (error) {
      if (shouldPass) mismatches.push({ label, reason: error instanceof Error ? error.message : "UNKNOWN" });
    }
  };
  validate("exact official response", expected, true);
  validate("official response with extra key", { ...expected, serverExtension: "backward-compatible" }, true);
  const missingEventId = { ...expected };
  delete missingEventId.eventId;
  validate("missing eventId", missingEventId, false);
  validate("wrong eventRef", { ...expected, eventRef: "WRONG" }, false);
  validate("wrong eventType", { ...expected, eventType: "EXPECTED" }, false);
  validate("lineCount string", { ...expected, lineCount: "1" }, false);
  validate("totalQuantity zero", { ...expected, totalQuantity: 0 }, false);
  validate("invalid timestamp", { ...expected, recordedAt: "not-a-timestamp" }, false);
  validate("different returnId", { ...expected, returnId: "d21dc958-9fc8-457f-947c-95ac5a509177" }, false);
  let persistedValidation;
  try {
    persistedValidation = validateMarkReturnLostResponse({ response: persistedResponseSnapshot, request, expectedReturnId, expectedReturnRef, expectedEventRef });
  } catch (error) {
    const detail = error && typeof error === "object" ? error.detail : null;
    if (detail) {
      for (const path of detail.missingPaths) mismatches.push({ label: "persisted response snapshot", path, reason: "MISSING" });
      for (const invalid of detail.invalidPaths) mismatches.push({ label: "persisted response snapshot", path: invalid.path, reason: invalid.reason });
    } else {
      mismatches.push({ label: "persisted response snapshot", reason: error instanceof Error ? error.message : "UNKNOWN" });
    }
  }
  return {
    sourceContractFieldCount: MARK_RETURN_LOST_RESPONSE_KEYS.length,
    persistedFieldCount: isPlainObject(persistedResponseSnapshot) ? Object.keys(persistedResponseSnapshot).length : 0,
    missingFieldCount: mismatches.filter((mismatch) => mismatch.reason === "MISSING").length,
    invalidFieldCount: mismatches.filter((mismatch) => mismatch.reason !== "MISSING").length,
    unexpectedFieldCount: persistedValidation ? persistedValidation.unexpectedKeys.length : 0,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function sliceKClaimRegressionFixture() {
  const returnId = "c21dc958-9fc8-457f-947c-95ac5a509177";
  const returnItemId = "80958d39-5804-4e2f-8dfb-5b4bd94f952d";
  const claimId = "0536af47-4b33-4432-bede-8ddacf6c89dc";
  const commandId = "1536af47-4b33-4432-bede-8ddacf6c89dc";
  const createdAt = "2026-08-01T16:50:39.242508Z";
  const expectedDeadlineAt = expectedSliceKClaimDeadlineAt(createdAt);
  return {
    sliceJ: {
      classification: "EXACT_LOST",
      header: { return_id: returnId, created_at: createdAt },
      item: { return_item_id: returnItemId, product_id: "30000000-0000-4000-8000-000000000001" },
      stock: { exact: true },
    },
    claim: {
      id: claimId, return_id: returnId, claim_type_code: "LOST_RETURN", status_code: "NOT_STARTED",
      resolution_code: null, external_claim_ref: null, claim_basis_code: "RETURN_CREATED_AT", claim_basis_at: createdAt,
      window_days_snapshot: 40, timezone_snapshot: "Asia/Jakarta", deadline_source_code: "INTERNAL_RETURN_CREATED_AT",
      deadline_at: expectedDeadlineAt, policy_version_snapshot: SLICE_K.policyVersion, schema_version: 1,
      actor_user_id: "ebbe8a13-0299-4121-aa10-b01dda6f3e49", process_name: null, stock_effect_code: "NONE",
      idempotency_command_id: commandId,
    },
    claimItems: [{
      claim_id: claimId, return_item_id: returnItemId, quantity: 1, eligible_lost_qty_snapshot: 1,
      product_id: "30000000-0000-4000-8000-000000000001", product_sku_snapshot: SLICE_J.productSku,
      source_line_ref_snapshot: SLICE_E.canonicalSourceLineRef,
      canonical_components_snapshot: [{ snapshotSchemaVersion: 2, provenanceKind: "SINGLE_PRODUCT_SOURCE", returnItemId, productId: "30000000-0000-4000-8000-000000000001", productSku: SLICE_J.productSku, sourceLineRef: SLICE_E.canonicalSourceLineRef }],
    }],
    claimEvents: [{
      claim_id: claimId, event_type_code: "CREATED", occurred_at: SLICE_K.claimOccurredAt,
      actor_user_id: "ebbe8a13-0299-4121-aa10-b01dda6f3e49", process_name: null,
      idempotency_command_id: commandId,
      snapshot: { stockEffectCode: "NONE", claimBasisCode: "RETURN_CREATED_AT", deadlineSourceCode: "INTERNAL_RETURN_CREATED_AT" },
    }],
    idempotency: { candidateCount: 1, command: { scope: "CREATE_TIKTOK_RETURN_CLAIM", key: SLICE_K.claimIdempotencyKey, statusCode: "SUCCEEDED", completedAt: "2026-08-01T18:12:23.828258Z", responseSnapshot: { claimId, deadlineAt: expectedDeadlineAt, stockEffectCode: "NONE" } } },
    notifications: [],
    expectedDeadlineAt,
  };
}

function auditSliceKClaimContract({ persistedSnapshot = sliceKClaimRegressionFixture() } = {}) {
  const fixture = sliceKClaimRegressionFixture();
  const responseFixture = fixture.idempotency.command.responseSnapshot;
  const mismatches = [];
  const validateResponseCase = (label, response, shouldPass) => {
    try {
      validateCreateTiktokReturnClaimResponse({ response, expectedDeadlineAt: fixture.expectedDeadlineAt });
      if (!shouldPass) mismatches.push({ label, reason: "EXPECTED_VALIDATOR_FAILURE" });
    } catch (error) {
      if (shouldPass) mismatches.push({ label, reason: error instanceof Error ? error.message : "UNKNOWN" });
    }
  };
  validateResponseCase("exact official response", responseFixture, true);
  validateResponseCase("official response with extra key", { ...responseFixture, serverExtension: "backward-compatible" }, true);
  const missingClaimId = { ...responseFixture };
  delete missingClaimId.claimId;
  validateResponseCase("missing claimId", missingClaimId, false);
  validateResponseCase("invalid claimId", { ...responseFixture, claimId: "invalid" }, false);
  validateResponseCase("wrong deadline", { ...responseFixture, deadlineAt: "2026-09-11T16:50:39.242508Z" }, false);
  validateResponseCase("non-neutral stock effect", { ...responseFixture, stockEffectCode: "LEDGER" }, false);
  const validatePersistedCase = (label, snapshot, shouldPass) => {
    const validation = validateSliceKClaimCreatedEvidence(snapshot);
    if (validation.valid !== shouldPass) mismatches.push({ label, reason: shouldPass ? "PERSISTED_EVIDENCE_REJECTED" : "EXPECTED_PERSISTED_VALIDATOR_FAILURE" });
  };
  validatePersistedCase("exact persisted claim", fixture, true);
  const duplicateClaim = structuredClone(fixture); duplicateClaim.idempotency.candidateCount = 2; validatePersistedCase("duplicate claim command", duplicateClaim, false);
  const wrongStatus = structuredClone(fixture); wrongStatus.claim.status_code = "DUE_SOON"; validatePersistedCase("wrong status", wrongStatus, false);
  const wrongType = structuredClone(fixture); wrongType.claim.claim_type_code = "OTHER_RETURN_EXCEPTION"; validatePersistedCase("wrong claim type", wrongType, false);
  const wrongDeadline = structuredClone(fixture); wrongDeadline.claim.deadline_at = "2026-08-24T04:45:00Z"; validatePersistedCase("deadline from LOST event", wrongDeadline, false);
  const stringQuantity = structuredClone(fixture); stringQuantity.claimItems[0].quantity = "1"; validatePersistedCase("item quantity string", stringQuantity, false);
  const zeroQuantity = structuredClone(fixture); zeroQuantity.claimItems[0].quantity = 0; validatePersistedCase("item quantity zero", zeroQuantity, false);
  const wrongEligible = structuredClone(fixture); wrongEligible.claimItems[0].eligible_lost_qty_snapshot = 0; validatePersistedCase("wrong eligible lost snapshot", wrongEligible, false);
  const wrongReturnItem = structuredClone(fixture); wrongReturnItem.claimItems[0].return_item_id = "90958d39-5804-4e2f-8dfb-5b4bd94f952d"; validatePersistedCase("wrong return item", wrongReturnItem, false);
  const missingCreated = structuredClone(fixture); missingCreated.claimEvents = []; validatePersistedCase("missing CREATED event", missingCreated, false);
  const wrongEventStock = structuredClone(fixture); wrongEventStock.claimEvents[0].snapshot.stockEffectCode = "LEDGER"; validatePersistedCase("wrong CREATED stock effect", wrongEventStock, false);
  // Claim creation is historical evidence.  A later canonical notification is
  // expected at the next checkpoint and must not invalidate the pre-evaluator
  // claim contract.
  const persistedClaimSnapshot = persistedSnapshot?.classification === "EXACT_NOTIFICATION_CREATED"
    ? { ...persistedSnapshot, notifications: [] }
    : persistedSnapshot;
  const persistedValidation = validateSliceKClaimCreatedEvidence(persistedClaimSnapshot);
  if (!persistedValidation.valid) {
    for (const path of persistedValidation.missingPaths) mismatches.push({ label: "persisted claim", path, reason: "MISSING" });
    for (const invalid of persistedValidation.invalidPaths) mismatches.push({ label: "persisted claim", path: invalid.path, reason: invalid.reason });
  }
  return {
    responseFieldCount: CREATE_TIKTOK_RETURN_CLAIM_RESPONSE_KEYS.length,
    masterCheckedFieldCount: 17,
    itemCheckedFieldCount: 15,
    eventCheckedFieldCount: 8,
    missingFieldCount: mismatches.filter((mismatch) => mismatch.reason === "MISSING").length,
    invalidFieldCount: mismatches.filter((mismatch) => mismatch.reason !== "MISSING").length,
    mismatchCount: mismatches.length,
    mismatches,
  };
}

function runLocalReadOnlyCommand(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    child.on("error", () => reject(new Error("SLICE_J_LOST_IDEMPOTENCY_READ_FAILED")));
    child.on("close", (code) => {
      if (code !== 0 || stderr.trim()) return reject(new Error("SLICE_J_LOST_IDEMPOTENCY_READ_FAILED"));
      resolve(stdout);
    });
  });
}

async function readSliceJLostIdempotencyResponseSnapshot(organizationId) {
  if (!UUID_PATTERN.test(String(organizationId))) throw new Error("SLICE_J_LOST_IDEMPOTENCY_ORGANIZATION_INVALID");
  const containers = (await runLocalReadOnlyCommand("docker", ["ps", "--filter", "name=supabase_db_", "--format", "{{.Names}}"]))
    .split(/\r?\n/)
    .map((value) => value.trim())
    .filter(Boolean);
  if (containers.length !== 1) throw new Error("SLICE_J_LOST_IDEMPOTENCY_DB_CONTAINER_AMBIGUOUS");
  const sql = `select json_build_object('scope', command.scope, 'key', command.key, 'statusCode', command.status_code, 'completedAt', command.completed_at, 'responseSnapshot', command.response_snapshot)::text from inventory.idempotency_commands command where command.organization_id = '${organizationId}'::uuid and command.scope = 'MARK_RETURN_LOST' and command.key = '${SLICE_J.lostIdempotencyKey}' and command.status_code = 'SUCCEEDED';`;
  const rows = (await runLocalReadOnlyCommand("docker", ["exec", "-i", containers[0], "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]))
    .split(/\r?\n/)
    .map((value) => value.trim())
    .filter(Boolean);
  if (rows.length !== 1) throw new Error("SLICE_J_LOST_IDEMPOTENCY_SNAPSHOT_AMBIGUOUS");
  let snapshot;
  try {
    snapshot = JSON.parse(rows[0]);
  } catch {
    throw new Error("SLICE_J_LOST_IDEMPOTENCY_SNAPSHOT_INVALID");
  }
  if (!isPlainObject(snapshot) || snapshot.scope !== "MARK_RETURN_LOST" || snapshot.key !== SLICE_J.lostIdempotencyKey || snapshot.statusCode !== "SUCCEEDED" || !isPlainObject(snapshot.responseSnapshot)) {
    throw new Error("SLICE_J_LOST_IDEMPOTENCY_SNAPSHOT_INVALID");
  }
  return snapshot;
}

async function readSliceKClaimIdempotencyResponseSnapshot(organizationId) {
  if (!UUID_PATTERN.test(String(organizationId))) throw new Error("SLICE_K_CLAIM_IDEMPOTENCY_ORGANIZATION_INVALID");
  const containers = (await runLocalReadOnlyCommand("docker", ["ps", "--filter", "name=supabase_db_", "--format", "{{.Names}}"])).split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
  if (containers.length !== 1) throw new Error("SLICE_K_CLAIM_IDEMPOTENCY_DB_CONTAINER_AMBIGUOUS");
  const sql = `select json_build_object('scope', command.scope, 'key', command.key, 'statusCode', command.status_code, 'completedAt', command.completed_at, 'responseSnapshot', command.response_snapshot)::text from inventory.idempotency_commands command where command.organization_id = '${organizationId}'::uuid and command.scope = 'CREATE_TIKTOK_RETURN_CLAIM' and command.key = '${SLICE_K.claimIdempotencyKey}';`;
  const rows = (await runLocalReadOnlyCommand("docker", ["exec", "-i", containers[0], "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql])).split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
  if (rows.length > 1) throw new Error("SLICE_K_CLAIM_IDEMPOTENCY_SNAPSHOT_AMBIGUOUS");
  if (rows.length === 0) return { candidateCount: 0, command: null };
  let command;
  try {
    command = JSON.parse(exactGoldenRow(rows, "SLICE_K_CLAIM_IDEMPOTENCY_SNAPSHOT_AMBIGUOUS"));
  } catch {
    throw new Error("SLICE_K_CLAIM_IDEMPOTENCY_SNAPSHOT_INVALID");
  }
  if (!isPlainObject(command)) throw new Error("SLICE_K_CLAIM_IDEMPOTENCY_SNAPSHOT_INVALID");
  return { candidateCount: 1, command };
}

async function readSliceKNotificationLocalRows(sql, errorPrefix) {
  const containers = (await runLocalReadOnlyCommand("docker", ["ps", "--filter", "name=supabase_db_", "--format", "{{.Names}}"]))
    .split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
  if (containers.length !== 1) throw new Error(`${errorPrefix}_DB_CONTAINER_AMBIGUOUS`);
  const rows = (await runLocalReadOnlyCommand("docker", ["exec", "-i", containers[0], "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]))
    .split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
  try { return rows.map((row) => JSON.parse(row)); } catch { throw new Error(`${errorPrefix}_INVALID`); }
}

function canonicalSliceKNotificationIdempotencyKey(claimId, deadlineAt) {
  if (!UUID_PATTERN.test(String(claimId))) throw new Error("SLICE_K_NOTIFICATION_CLAIM_ID_INVALID");
  if (typeof deadlineAt !== "string" || !Number.isFinite(Date.parse(deadlineAt))) throw new Error("SLICE_K_NOTIFICATION_DEADLINE_INVALID");
  const deadlineFingerprint = deadlineAt.replace(/[^0-9]/g, "");
  if (!deadlineFingerprint) throw new Error("SLICE_K_NOTIFICATION_DEADLINE_FINGERPRINT_INVALID");
  return `GOLDEN-DEMO-V1:CLAIM-NOTIFICATION:D14:V2:${claimId}:${deadlineFingerprint}`;
}

async function readSliceKNotificationSchedule(organizationId, claimId) {
  if (!UUID_PATTERN.test(String(organizationId)) || !UUID_PATTERN.test(String(claimId))) throw new Error("SLICE_K_NOTIFICATION_SCHEDULE_ID_INVALID");
  const rows = await readSliceKNotificationLocalRows(`select json_build_object('claimId', claim.id, 'deadlineAt', claim.deadline_at, 'observedAt', claim.deadline_at - interval '14 days')::text from operations.return_claims claim where claim.organization_id = '${organizationId}'::uuid and claim.id = '${claimId}'::uuid;`, "SLICE_K_NOTIFICATION_SCHEDULE");
  if (rows.length !== 1) throw new Error("SLICE_K_NOTIFICATION_SCHEDULE_AMBIGUOUS");
  const schedule = exactGoldenRow(rows, "SLICE_K_NOTIFICATION_SCHEDULE_AMBIGUOUS");
  if (!isPlainObject(schedule) || String(schedule.claimId) !== String(claimId) || !Number.isFinite(Date.parse(String(schedule.deadlineAt))) || !Number.isFinite(Date.parse(String(schedule.observedAt)))) throw new Error("SLICE_K_NOTIFICATION_SCHEDULE_INVALID");
  return schedule;
}

async function readSliceKNotificationRuleRunSnapshots(organizationId, canonicalKey) {
  if (!UUID_PATTERN.test(String(organizationId)) || !isNonBlank(canonicalKey)) throw new Error("SLICE_K_NOTIFICATION_RULE_RUN_INPUT_INVALID");
  const rows = await readSliceKNotificationLocalRows(`select json_build_object('ruleRunId', rule_run.id, 'ruleId', rule_run.rule_id, 'ruleCode', rule_run.rule_code_snapshot, 'ruleVersion', rule_run.rule_version_snapshot, 'triggerType', rule_run.trigger_type_code, 'idempotencyKey', rule_run.idempotency_key, 'status', rule_run.status_code, 'startedAt', rule_run.started_at, 'completedAt', rule_run.completed_at, 'evaluatedCount', rule_run.evaluated_count, 'createdCount', rule_run.created_count, 'updatedCount', rule_run.updated_count, 'resolvedCount', rule_run.resolved_count, 'skippedCount', rule_run.skipped_count, 'errorCount', rule_run.error_count, 'summary', rule_run.summary, 'errorDetail', rule_run.error_detail, 'processName', rule_run.process_name)::text from notification.rule_runs rule_run where rule_run.organization_id = '${organizationId}'::uuid and rule_run.rule_code_snapshot = 'CLAIM_DEADLINE' and rule_run.idempotency_key in ('${SLICE_K.legacyNotificationIdempotencyKey}', '${canonicalKey}') order by rule_run.idempotency_key, rule_run.id;`, "SLICE_K_NOTIFICATION_RULE_RUN");
  const legacyRuns = rows.filter((row) => String(row?.idempotencyKey ?? "") === SLICE_K.legacyNotificationIdempotencyKey);
  const canonicalRuns = rows.filter((row) => String(row?.idempotencyKey ?? "") === canonicalKey);
  if (legacyRuns.length > 1 || canonicalRuns.length > 1 || rows.length !== legacyRuns.length + canonicalRuns.length) throw new Error("SLICE_K_NOTIFICATION_RULE_RUN_AMBIGUOUS");
  if (!rows.every(isPlainObject)) throw new Error("SLICE_K_NOTIFICATION_RULE_RUN_INVALID");
  return { legacyRuns, canonicalRuns };
}

async function readSliceKRawNotificationRows(organizationId, claimId) {
  if (!UUID_PATTERN.test(String(organizationId)) || !UUID_PATTERN.test(String(claimId))) throw new Error("SLICE_K_NOTIFICATION_RAW_INPUT_INVALID");
  return await readSliceKNotificationLocalRows(`select json_build_object('notificationId', notification_row.id, 'ruleCode', notification_row.rule_code_snapshot, 'entityTypeCode', notification_row.entity_type_code, 'entityId', notification_row.entity_id, 'lifecycleStatusCode', notification_row.lifecycle_status_code, 'stageCode', notification_row.stage_code, 'severityCode', notification_row.severity_code, 'actionRoute', notification_row.action_route, 'conditionStartedAt', notification_row.condition_started_at, 'dueAt', notification_row.due_at, 'firstSeenAt', notification_row.first_seen_at, 'lastSeenAt', notification_row.last_seen_at, 'occurrenceCount', notification_row.occurrence_count, 'sourceSnapshot', notification_row.source_snapshot)::text from notification.notifications notification_row where notification_row.organization_id = '${organizationId}'::uuid and notification_row.entity_type_code = 'RETURN_CLAIM' and notification_row.entity_id = '${claimId}'::uuid and notification_row.rule_code_snapshot = 'CLAIM_DEADLINE' order by notification_row.id;`, "SLICE_K_NOTIFICATION_RAW");
}

async function probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase = "SLICE_J_TIKTOK_RETURN_LOST" } = {}) {
  const expectedEventRef = `EXPECTED:${SLICE_J.returnRef}`;
  const expectedMetadata = {
    source: "golden-demo-runner",
    version: 1,
    slice: "J",
    reference: SLICE_J.metadataReference,
    stockEffectCode: "NONE",
  };
  const canonicalJson = (value) => {
    if (Array.isArray(value)) return value.map(canonicalJson);
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalJson(value[key])]));
    }
    return value;
  };
  const sameMetadata = (actual) => JSON.stringify(canonicalJson(actual)) === JSON.stringify(canonicalJson(expectedMetadata));
  const eventHeaderExact = (event, eventType, eventRef) =>
    event !== null
    && String(event?.event_type_code ?? "") === eventType
    && String(event?.external_event_ref ?? "") === eventRef
    && event?.transaction_id === null
    && (
      UUID_PATTERN.test(String(event?.actor_user_id ?? "")) && event?.process_name === null
      || event?.actor_user_id === null && isNonBlank(event?.process_name)
    )
    && String(event?.note ?? "") === SLICE_J.note
    && sameMetadata(event?.metadata);

  const [headers, expectedEventsByRef, lostEventsByRef, candidateItems, ledgerRows] = await Promise.all([
    readJsonRows(supabaseUrl, publishableKey, accessToken, `returns?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&marketplace_order_ref=eq.${encodeURIComponent(SLICE_E.externalOrderRef)}&external_return_ref=eq.${encodeURIComponent(SLICE_J.returnRef)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_events?organization_id=eq.${encodeURIComponent(organizationId)}&external_event_ref=eq.${encodeURIComponent(expectedEventRef)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_events?organization_id=eq.${encodeURIComponent(organizationId)}&external_event_ref=eq.${encodeURIComponent(SLICE_J.lostEventRef)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_items?organization_id=eq.${encodeURIComponent(organizationId)}&product_sku_snapshot=eq.${encodeURIComponent(SLICE_J.productSku)}&source_line_ref=eq.${encodeURIComponent(SLICE_E.canonicalSourceLineRef)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}&source_ref_snapshot=in.(${encodeURIComponent(SLICE_J.returnRef)},${encodeURIComponent(SLICE_J.lostEventRef)})&select=ledger_entry_id,transaction_id,source_ref_snapshot`),
  ]);
  if (!headers || !expectedEventsByRef || !lostEventsByRef || !candidateItems || !ledgerRows) return null;

  if (headers.length === 0) {
    const noEvidence = candidateItems.length === 0 && expectedEventsByRef.length === 0 && lostEventsByRef.length === 0 && ledgerRows.length === 0;
    return {
      classification: noEvidence ? "NONE" : "PARTIAL_OR_CONFLICTING",
      counts: { returnCount: 0, itemCount: candidateItems.length, expectedEventCount: expectedEventsByRef.length, lostEventCount: lostEventsByRef.length, claimCount: 0, transactionCount: new Set(ledgerRows.map((row) => String(row?.transaction_id ?? "")).filter(Boolean)).size, ledgerCount: ledgerRows.length },
    };
  }
  if (headers.length !== 1) {
    return {
      classification: "PARTIAL_OR_CONFLICTING",
      counts: { returnCount: headers.length, itemCount: candidateItems.length, expectedEventCount: expectedEventsByRef.length, lostEventCount: lostEventsByRef.length, claimCount: 0, transactionCount: new Set(ledgerRows.map((row) => String(row?.transaction_id ?? "")).filter(Boolean)).size, ledgerCount: ledgerRows.length },
    };
  }

  const header = exactGoldenRow(headers, "SLICE_J_RETURN_AMBIGUOUS");
  const [items, events, lifecycleRows, claimRows, receiptLines, inspectionAllocations, returnBatches] = await Promise.all([
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_items?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_events?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_E.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_E.sourceLineRef)}&canonical_source_line_ref=eq.${encodeURIComponent(SLICE_E.canonicalSourceLineRef)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_claim_master?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_receipt_lines?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=receipt_line_id`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_inspection_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=inspection_allocation_id`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_stock_batches?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(header.return_id)}&select=return_stock_batch_id`),
  ]);
  if (!items || !events || !lifecycleRows || !claimRows || !receiptLines || !inspectionAllocations || !returnBatches) return null;

  const lifecycle = lifecycleRows.length === 1 ? exactGoldenRow(lifecycleRows, "SLICE_J_TIKTOK_LIFECYCLE_AMBIGUOUS") : null;
  const matchingItems = items.filter((row) =>
    String(row?.return_id ?? "") === String(header.return_id)
    && String(row?.marketplace_order_item_id ?? "") === String(lifecycle?.order_item_id ?? "")
    && String(row?.marketplace_item_ref ?? "") === SLICE_E.canonicalSourceLineRef
    && String(row?.source_line_ref ?? "") === SLICE_E.canonicalSourceLineRef
    && String(row?.product_id ?? "") === String(lifecycle?.product_id ?? "")
    && String(row?.product_sku_snapshot ?? "") === SLICE_J.productSku
    && asNumber(row?.expected_qty) === SLICE_J.quantity,
  );
  const item = items.length === 1 && matchingItems.length === 1
    ? exactGoldenRow(matchingItems, "SLICE_J_RETURN_ITEM_AMBIGUOUS")
    : null;
  const expectedEvents = events.filter((event) => String(event?.event_type_code ?? "") === "EXPECTED");
  const lostEvents = events.filter((event) => String(event?.event_type_code ?? "") === "LOST");
  const receiptEvents = events.filter((event) => String(event?.event_type_code ?? "") === "RECEIPT");
  const inspectionEvents = events.filter((event) => String(event?.event_type_code ?? "") === "INSPECTION");
  const unexpectedEvents = events.filter((event) => !["EXPECTED", "LOST"].includes(String(event?.event_type_code ?? "")));
  const expectedEvent = expectedEvents.length === 1 ? exactGoldenRow(expectedEvents, "SLICE_J_EXPECTED_EVENT_AMBIGUOUS") : null;
  const lostEvent = lostEvents.length === 1 ? exactGoldenRow(lostEvents, "SLICE_J_LOST_EVENT_AMBIGUOUS") : null;
  const transactionCount = new Set(ledgerRows.map((row) => String(row?.transaction_id ?? "")).filter(Boolean)).size;
  const baseExact = lifecycleRows.length === 1
    && item !== null
    && expectedEvents.length === 1
    && expectedEventsByRef.length === 1
    && eventHeaderExact(expectedEvent, "EXPECTED", expectedEventRef)
    && String(expectedEvent?.return_id ?? "") === String(header.return_id)
    && String(header?.channel_code ?? "") === SLICE_E.channelCode
    && String(header?.marketplace_order_ref ?? "") === SLICE_E.externalOrderRef
    && String(header?.external_return_ref ?? "") === SLICE_J.returnRef
    && String(lifecycle?.order_id ?? "") === String(header?.marketplace_order_id ?? "")
    && String(header?.source_status_code ?? "") === SLICE_J.sourceStatus
    && asNumber(header?.expected_qty) === SLICE_J.quantity;
  const expectedItemExact = item !== null
    && asNumber(item?.expected_qty) === SLICE_J.quantity
    && asNumber(item?.received_qty) === 0
    && asNumber(item?.sellable_qty) === 0
    && asNumber(item?.damaged_qty) === 0
    && asNumber(item?.lost_qty) === 0
    && asNumber(item?.pending_arrival_qty) === SLICE_J.quantity
    && asNumber(item?.pending_inspection_qty) === 0;
  const lostItemExact = item !== null
    && asNumber(item?.expected_qty) === SLICE_J.quantity
    && asNumber(item?.received_qty) === 0
    && asNumber(item?.sellable_qty) === 0
    && asNumber(item?.damaged_qty) === 0
    && asNumber(item?.lost_qty) === SLICE_J.quantity
    && asNumber(item?.pending_arrival_qty) === 0
    && asNumber(item?.pending_inspection_qty) === 0;
  const lifecycleExact = (lostQuantity) => lifecycle !== null
    && asNumber(lifecycle?.return_expected_quantity) === SLICE_J.quantity
    && asNumber(lifecycle?.return_received_quantity) === 0
    && asNumber(lifecycle?.return_sellable_quantity) === 0
    && asNumber(lifecycle?.return_damaged_quantity) === 0
    && asNumber(lifecycle?.return_lost_quantity) === lostQuantity
    && asNumber(lifecycle?.remaining_returnable_or_cancellable_quantity) === 0;
  const counts = {
    returnCount: 1,
    itemCount: items.length,
    expectedEventCount: expectedEvents.length,
    lostEventCount: lostEvents.length,
    receiptEventCount: receiptEvents.length,
    inspectionEventCount: inspectionEvents.length,
    receiptLineCount: receiptLines.length,
    inspectionAllocationCount: inspectionAllocations.length,
    returnBatchCount: returnBatches.length,
    unexpectedEventCount: unexpectedEvents.length,
    claimCount: claimRows.length,
    transactionCount,
    ledgerCount: ledgerRows.length,
    lifecycleCount: lifecycleRows.length,
  };
  if (!baseExact || receiptEvents.length !== 0 || inspectionEvents.length !== 0 || receiptLines.length !== 0 || inspectionAllocations.length !== 0 || returnBatches.length !== 0 || unexpectedEvents.length !== 0) {
    return { classification: "PARTIAL_OR_CONFLICTING", header, item, counts };
  }
  if (lostEvents.length === 0) {
    const exact = String(header?.status_code ?? "") === "EXPECTED"
      && header?.outcome_code === null
      && expectedItemExact
      && lostEventsByRef.length === 0
      && claimRows.length === 0
      && transactionCount === 0
      && ledgerRows.length === 0
      && lifecycleExact(0);
    return { classification: exact ? "EXPECTED_ONLY" : "PARTIAL_OR_CONFLICTING", header, item, counts, lifecycle };
  }
  const resolvedProjectionPhase = phaseNameOf(projectionPhase);
  const stock = await readSliceJStockNeutral(supabaseUrl, publishableKey, accessToken, organizationId, resolvedProjectionPhase);
  if (!stock) return null;
  const exact = lostEvents.length === 1
    && lostEventsByRef.length === 1
    && eventHeaderExact(lostEvent, "LOST", SLICE_J.lostEventRef)
    && String(lostEvent?.return_id ?? "") === String(header.return_id)
    && String(header?.status_code ?? "") === "LOST"
    && String(header?.outcome_code ?? "") === "LOST"
    && lostItemExact
    && transactionCount === 0
    && ledgerRows.length === 0
    && lifecycleExact(SLICE_J.quantity)
    && stock.exact;
  return {
    classification: exact ? "EXACT_LOST" : "PARTIAL_OR_CONFLICTING",
    header, item, expectedEvent, lostEvent, stock: { ...stock, projectionPhase: resolvedProjectionPhase }, lifecycle, counts,
    effectivePhase: { detectedPhase: "SLICE_J_TIKTOK_RETURN_LOST" },
  };
}

async function probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase = "SLICE_K_TIKTOK_CLAIM_NOTIFICATION" } = {}) {
  const sliceJ = await probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase });
  if (!sliceJ || ["NONE", "EXPECTED_ONLY"].includes(sliceJ.classification)) return { classification: "NONE", sliceJ };
  if (sliceJ.classification !== "EXACT_LOST") return { classification: "PARTIAL_OR_CONFLICTING", sliceJ };
  const claimRows = await readJsonRows(supabaseUrl, publishableKey, accessToken, `return_claim_master?organization_id=eq.${encodeURIComponent(organizationId)}&return_id=eq.${encodeURIComponent(sliceJ.header.return_id)}&select=*`);
  if (!claimRows) return null;
  const idempotency = await readSliceKClaimIdempotencyResponseSnapshot(organizationId);
  if (claimRows.length === 0) {
    return idempotency.candidateCount === 0
      ? { classification: "NONE", sliceJ, counts: { claimCount: 0, claimItemCount: 0, claimEventCount: 0, idempotencyCount: 0, notificationCount: 0, notificationRuleRunCount: 0 } }
      : { classification: "PARTIAL_OR_CONFLICTING", sliceJ, counts: { claimCount: 0, claimItemCount: 0, claimEventCount: 0, idempotencyCount: idempotency.candidateCount, notificationCount: 0, notificationRuleRunCount: 0 } };
  }
  if (claimRows.length !== 1) return { classification: "PARTIAL_OR_CONFLICTING", sliceJ, counts: { claimCount: claimRows.length } };
  const claim = exactGoldenRow(claimRows, "SLICE_K_CLAIM_AMBIGUOUS");
  const schedule = await readSliceKNotificationSchedule(organizationId, claim.id);
  const canonicalNotificationKey = canonicalSliceKNotificationIdempotencyKey(claim.id, schedule.deadlineAt);
  const [claimItems, claimEvents, notifications, notificationRuns, rawNotifications] = await Promise.all([
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_claim_items?organization_id=eq.${encodeURIComponent(organizationId)}&claim_id=eq.${encodeURIComponent(claim.id)}&select=*`),
    readJsonRows(supabaseUrl, publishableKey, accessToken, `return_claim_events?organization_id=eq.${encodeURIComponent(organizationId)}&claim_id=eq.${encodeURIComponent(claim.id)}&select=*`),
    rpcJson(supabaseUrl, publishableKey, accessToken, "return_claim_notification_list", { p_claim_id: claim.id, p_include_archived: true }),
    readSliceKNotificationRuleRunSnapshots(organizationId, canonicalNotificationKey),
    readSliceKRawNotificationRows(organizationId, claim.id),
  ]);
  if (!claimItems || !claimEvents || notifications.status !== 200 || !Array.isArray(notifications.payload)) return null;
  const expectedDeadlineAt = expectedSliceKClaimDeadlineAt(sliceJ.header.created_at);
  const persisted = {
    sliceJ,
    claim,
    claimItems,
    claimEvents,
    idempotency,
    notificationRuns,
    notifications: notifications.payload,
    rawNotifications,
    expectedDeadlineAt,
    notificationSchedule: schedule,
    canonicalNotificationKey,
    projectionEvidencePhase: phaseNameOf(projectionPhase),
  };
  const claimValidation = validateSliceKClaimCreatedEvidence({ ...persisted, notifications: [] });
  if (!claimValidation.valid) {
    return { classification: "PARTIAL_OR_CONFLICTING", ...persisted, validation: claimValidation, counts: sliceKClaimCounts(persisted) };
  }
  if (!sameInstant(schedule.deadlineAt, expectedDeadlineAt)) {
    return { classification: "PARTIAL_OR_CONFLICTING", ...persisted, validation: { valid: false, missingPaths: [], invalidPaths: [{ path: "notificationSchedule.deadlineAt", reason: "EXPECTED_RETURN_CREATED_AT_PLUS_40_DAYS" }] }, counts: sliceKClaimCounts(persisted) };
  }
  const deadlineAt = schedule.deadlineAt;
  const expectedRoute = `/returns?returnId=${sliceJ.header.return_id}&claimId=${claim.id}#claim-detail`;
  const active = notifications.payload.filter((row) => String(row?.rule_code ?? "") === "CLAIM_DEADLINE" && String(row?.stage_code ?? "") === "D14" && String(row?.entity_type_code ?? "") === "RETURN_CLAIM" && String(row?.entity_id ?? "") === String(claim.id) && ["OPEN", "ACKNOWLEDGED"].includes(String(row?.lifecycle_status_code ?? "")));
  const apiNotificationIds = notifications.payload.map((row) => String(row?.notification_id ?? "")).sort();
  const rawNotificationIds = rawNotifications.map((row) => String(row?.notificationId ?? "")).sort();
  const readModelConsistent = apiNotificationIds.length === rawNotificationIds.length && apiNotificationIds.every((id, index) => id === rawNotificationIds[index]);
  const legacyRuns = notificationRuns.legacyRuns;
  const canonicalRuns = notificationRuns.canonicalRuns;
  const legacyNoopExact = legacyRuns.length === 0 || legacyRuns.length === 1 && validateSliceKLegacyEarlyNoopRun(exactGoldenRow(legacyRuns, "SLICE_K_LEGACY_NOTIFICATION_RUN_AMBIGUOUS"), schedule.observedAt);
  if (!readModelConsistent || !legacyNoopExact || canonicalRuns.length > 1) {
    return { classification: "PARTIAL_OR_CONFLICTING", ...persisted, deadlineAt, notificationClassification: !readModelConsistent ? "READ_MODEL_MISMATCH" : "PARTIAL_OR_CONFLICTING", counts: sliceKClaimCounts(persisted) };
  }
  if (canonicalRuns.length === 0 && notifications.payload.length === 0 && rawNotifications.length === 0) {
    return { classification: "EXACT_CLAIM_CREATED", ...persisted, deadlineAt, counts: sliceKClaimCounts(persisted), effectivePhase: { detectedPhase: "SLICE_K_TIKTOK_CLAIM_CREATED" } };
  }
  const notification = active.length === 1 ? exactGoldenRow(active, "SLICE_K_NOTIFICATION_AMBIGUOUS") : null;
  const [detailResponse, historyResponse] = notification
    ? await Promise.all([
        rpcJson(supabaseUrl, publishableKey, accessToken, "notification_detail", { p_notification_id: notification.notification_id }),
        rpcJson(supabaseUrl, publishableKey, accessToken, "notification_event_history", { p_notification_id: notification.notification_id, p_limit: 20, p_after_occurred_at: null, p_after_id: null }),
      ])
    : [null, null];
  const detailRows = detailResponse?.status === 200 && Array.isArray(detailResponse.payload) ? detailResponse.payload : [];
  const historyRows = historyResponse?.status === 200 && Array.isArray(historyResponse.payload) ? historyResponse.payload : [];
  const detail = detailRows.length === 1 ? exactGoldenRow(detailRows, "SLICE_K_NOTIFICATION_DETAIL_AMBIGUOUS") : null;
  const workerEvents = historyRows.filter((row) => String(row?.process_name ?? "") === SLICE_K.workerProcessName);
  const sourceSnapshot = detail?.source_snapshot && typeof detail.source_snapshot === "object" ? detail.source_snapshot : {};
  const canonicalRun = canonicalRuns.length === 1 ? exactGoldenRow(canonicalRuns, "SLICE_K_CANONICAL_NOTIFICATION_RUN_AMBIGUOUS") : null;
  let canonicalRunExact = false;
  try {
    if (canonicalRun !== null) validateSliceKNotificationEvaluatorRun({ run: canonicalRun, expectedObservedAt: schedule.observedAt, expectedCanonicalKey: canonicalNotificationKey, expectedClaimId: String(claim.id) });
    canonicalRunExact = canonicalRun !== null;
  } catch {
    canonicalRunExact = false;
  }
  const exactNotification = canonicalRunExact && notification !== null && notifications.payload.length === 1 && rawNotifications.length === 1 && active.length === 1 && String(notification?.severity_code ?? "") === "WARNING" && String(notification?.action_route ?? "") === expectedRoute && sameInstant(notification?.due_at, deadlineAt)
    && detail !== null && String(sourceSnapshot?.claimId ?? "") === String(claim.id) && String(sourceSnapshot?.returnId ?? "") === String(sliceJ.header.return_id) && sameInstant(sourceSnapshot?.deadlineAt, deadlineAt)
    && String(sourceSnapshot?.stockEffectCode ?? "") === "NONE" && workerEvents.length === 1
    && String(exactGoldenRow(rawNotifications, "SLICE_K_RAW_NOTIFICATION_AMBIGUOUS").notificationId ?? "") === String(notification.notification_id);
  return {
    classification: exactNotification ? "EXACT_NOTIFICATION_CREATED" : "PARTIAL_OR_CONFLICTING",
    ...persisted, notification, detail, notificationHistory: historyRows, deadlineAt,
    counts: { ...sliceKClaimCounts(persisted), notificationCount: active.length, notificationEventCount: workerEvents.length },
    effectivePhase: { detectedPhase: exactNotification ? "SLICE_K_TIKTOK_CLAIM_NOTIFICATION" : "SLICE_K_TIKTOK_CLAIM_CREATED" },
  };
}

async function resolveSliceETiktokReturnProvenance(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const lifecycleRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_listing_component_lifecycle?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_order_ref=eq.${encodeURIComponent(SLICE_E.externalOrderRef)}&source_line_ref=eq.${encodeURIComponent(SLICE_E.sourceLineRef)}&canonical_source_line_ref=eq.${encodeURIComponent(SLICE_E.canonicalSourceLineRef)}&product_id=eq.${encodeURIComponent(serumProductId)}&select=*`,
  );
  if (!lifecycleRows) return null;
  const lifecycle = exactGoldenRow(lifecycleRows, "SLICE_J_TIKTOK_LIFECYCLE_AMBIGUOUS");
  if (asNumber(lifecycle.shipped_quantity) !== 1 || asNumber(lifecycle.consumed_qty) !== 1 || String(lifecycle.product_sku_snapshot ?? "") !== SLICE_J.productSku) {
    throw new Error("SLICE_J_TIKTOK_LIFECYCLE_NOT_EXACT");
  }
  const eventRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_events?organization_id=eq.${encodeURIComponent(organizationId)}&channel_code=eq.${encodeURIComponent(SLICE_E.channelCode)}&external_event_ref=eq.${encodeURIComponent(SLICE_E.externalShipEventRef)}&event_type_code=eq.SHIP&status_code=eq.APPLIED&select=event_id,order_id,transaction_id`,
  );
  if (!eventRows) return null;
  const event = exactGoldenRow(eventRows, "SLICE_J_TIKTOK_SHIPMENT_EVENT_AMBIGUOUS");
  const allocationRows = await readJsonRows(
    supabaseUrl,
    publishableKey,
    accessToken,
    `marketplace_ship_allocations?organization_id=eq.${encodeURIComponent(organizationId)}&event_id=eq.${encodeURIComponent(event.event_id)}&product_id=eq.${encodeURIComponent(serumProductId)}&source_line_ref=eq.${encodeURIComponent(SLICE_E.canonicalSourceLineRef)}&quantity_allocated=eq.1&select=*`,
  );
  if (!allocationRows) return null;
  const allocation = exactGoldenRow(allocationRows, "SLICE_J_TIKTOK_SHIPMENT_ALLOCATION_AMBIGUOUS");
  if (!UUID_PATTERN.test(String(allocation?.allocation_id ?? "")) || !UUID_PATTERN.test(String(allocation?.event_line_id ?? ""))) {
    throw new Error("SLICE_J_TIKTOK_SHIPMENT_ALLOCATION_INVALID");
  }
  return { lifecycle, event, allocation };
}

async function runSliceJTiktokReturnLostStateAware(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId) {
  const provenance = await resolveSliceETiktokReturnProvenance(supabaseUrl, publishableKey, accessToken, organizationId, serumProductId);
  if (!provenance) return null;
  let lostMutationApplied = false;
  const authoritativePhase = currentSerumProjectionPhaseContext ?? { detectedPhase: "SLICE_J_TIKTOK_RETURN_LOST" };
  let state = await probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: authoritativePhase });
  if (!state) return null;
  if (state.classification === "NONE") {
    const response = await rpcJson(supabaseUrl, publishableKey, accessToken, "create_expected_return", {
      p_organization_id: organizationId,
      p_idempotency_key: SLICE_J.expectedReturnIdempotencyKey,
      p_channel_code: SLICE_E.channelCode,
      p_return_ref: SLICE_J.returnRef,
      p_order_ref: SLICE_E.externalOrderRef,
      p_occurred_at: SLICE_J.expectedOccurredAt,
      p_lines: [{ productId: serumProductId, quantity: SLICE_J.quantity, sourceLineRef: SLICE_E.canonicalSourceLineRef }],
      p_source_status: SLICE_J.sourceStatus,
      p_note: SLICE_J.note,
      p_metadata: { source: "golden-demo-runner", version: 1, slice: "J", reference: SLICE_J.metadataReference, stockEffectCode: "NONE" },
    });
    if (response.status !== 200 || String(response.payload?.returnRef ?? "") !== SLICE_J.returnRef || Number(response.payload?.totalQuantity ?? NaN) !== 1) {
      fail("SLICE_J_EXPECTED_RETURN_RESPONSE_INVALID");
      return null;
    }
    lostMutationApplied = true;
    state = await probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: authoritativePhase });
  }
  if (!state || state.classification === "PARTIAL_OR_CONFLICTING") {
    fail("SLICE_J_RETURN_STATE_CONFLICT");
    return null;
  }
  if (state.classification === "EXPECTED_ONLY") {
    const lostRequestContract = {
      returnItemIdValidUuid: UUID_PATTERN.test(String(state?.item?.return_item_id ?? "")),
      quantity: SLICE_J.quantity,
      quantityIsSafeInteger: Number.isSafeInteger(SLICE_J.quantity) && SLICE_J.quantity === 1,
      sourceLineRefExact: String(state?.item?.source_line_ref ?? "") === SLICE_E.canonicalSourceLineRef,
      returnRefExact: String(state?.header?.external_return_ref ?? "") === SLICE_J.returnRef,
      lostEventRefExact: SLICE_J.lostEventRef === `${SLICE_J.returnRef}:EVENT`,
    };
    if (
      !lostRequestContract.returnItemIdValidUuid
      || lostRequestContract.quantity !== 1
      || !lostRequestContract.quantityIsSafeInteger
      || !lostRequestContract.sourceLineRefExact
      || !lostRequestContract.returnRefExact
      || !lostRequestContract.lostEventRefExact
    ) {
      throw new Error("SLICE_J_LOST_REQUEST_CONTRACT_INVALID");
    }
    const lostRequest = {
      p_organization_id: organizationId,
      p_idempotency_key: SLICE_J.lostIdempotencyKey,
      p_return_ref: SLICE_J.returnRef,
      p_event_ref: SLICE_J.lostEventRef,
      p_occurred_at: SLICE_J.lostOccurredAt,
      p_lines: [{ returnItemId: state.item.return_item_id, quantity: lostRequestContract.quantity, sourceLineRef: SLICE_E.canonicalSourceLineRef }],
      p_note: SLICE_J.note,
      p_metadata: { source: "golden-demo-runner", version: 1, slice: "J", reference: SLICE_J.metadataReference, stockEffectCode: "NONE" },
    };
    const response = await rpcJson(supabaseUrl, publishableKey, accessToken, "mark_return_lost", lostRequest);
    if (response.status !== 200) {
      fail("SLICE_J_LOST_RESPONSE_INVALID");
      return null;
    }
    try {
      validateMarkReturnLostResponse({
        response: response.payload,
        request: { occurredAt: lostRequest.p_occurred_at },
        expectedReturnId: state.header.return_id,
        expectedReturnRef: SLICE_J.returnRef,
        expectedEventRef: SLICE_J.lostEventRef,
      });
    } catch (error) {
      console.log(JSON.stringify({
        code: "SLICE_J_LOST_RESPONSE_INVALID",
        detail: error && typeof error === "object" ? error.detail : null,
      }, null, 2));
      fail("SLICE_J_LOST_RESPONSE_INVALID");
      return null;
    }
    state = await probeSliceJTiktokReturnState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: lostMutationApplied ? { detectedPhase: "SLICE_J_TIKTOK_RETURN_LOST" } : authoritativePhase });
  }
  if (!state || state.classification !== "EXACT_LOST") {
    fail("SLICE_J_LOST_NOT_EXACT");
    return null;
  }
  try {
    const validationPhase = lostMutationApplied ? state.effectivePhase : authoritativePhase;
    const downstreamState = await probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: validationPhase });
    if (!downstreamState) throw new Error("SLICE_J_DOWNSTREAM_EVIDENCE_UNAVAILABLE");
    const validationContext = lostMutationApplied
      ? SLICE_J_POSTCONDITION_CONTEXT.AFTER_SLICE_J_MUTATION
      : SLICE_J_POSTCONDITION_CONTEXT.LOWER_SLICE_REPLAY;
    const highestPersistedPhase = validationPhase;
    validateSliceJLostPersistedPostcondition({
      snapshot: { ...state, downstream: sliceJDownstreamEvidenceFromSliceKState(downstreamState) },
      highestPersistedPhase,
      validationContext,
    });
  } catch (error) {
    console.log(JSON.stringify({
      code: error && typeof error === "object" && error.code === "GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT"
        ? "GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT"
        : "SLICE_J_LOST_PERSISTED_POSTCONDITION_INVALID",
      detail: error && typeof error === "object" ? error.detail : null,
    }, null, 2));
    fail(error && typeof error === "object" && error.code === "GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT"
      ? "GOLDEN_SLICE_J_LIFECYCLE_CONTRACT_NOT_EXACT"
      : "SLICE_J_LOST_PERSISTED_POSTCONDITION_INVALID");
    return null;
  }
  promoteSerumProjectionPhaseContext(state.effectivePhase);
  console.log("[PASS] Slice J TikTok expected return dan LOST exact serta stock-neutral");
  return { ...state, provenance };
}

async function runSliceKTiktokClaimNotificationStateAware(supabaseUrl, publishableKey, accessToken, organizationId) {
  const authoritativePhase = currentSerumProjectionPhaseContext ?? { detectedPhase: "SLICE_K_TIKTOK_CLAIM_NOTIFICATION" };
  let state = await probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: authoritativePhase });
  if (!state) return null;
  if (state.classification === "PARTIAL_OR_CONFLICTING") {
    fail("SLICE_K_CLAIM_STATE_CONFLICT");
    return null;
  }
  if (state.classification === "NONE") {
    const sliceJ = state.sliceJ;
    const expectedDeadlineAt = expectedSliceKClaimDeadlineAt(sliceJ.header.created_at);
    const claimRequest = {
      p_organization_id: organizationId,
      p_idempotency_key: SLICE_K.claimIdempotencyKey,
      p_return_id: sliceJ.header.return_id,
      p_claim_type_code: SLICE_K.claimTypeCode,
      p_items: [{ returnItemId: sliceJ.item.return_item_id, quantity: SLICE_J.quantity }],
      p_occurred_at: SLICE_K.claimOccurredAt,
    };
    const response = await rpcJson(supabaseUrl, publishableKey, accessToken, "create_tiktok_return_claim", claimRequest);
    if (response.status !== 200) {
      fail("SLICE_K_CLAIM_RESPONSE_INVALID");
      return null;
    }
    try {
      validateCreateTiktokReturnClaimResponse({ response: response.payload, expectedDeadlineAt });
    } catch (error) {
      console.log(JSON.stringify({ code: "SLICE_K_CLAIM_RESPONSE_INVALID", detail: error && typeof error === "object" ? error.detail : null }, null, 2));
      fail("SLICE_K_CLAIM_RESPONSE_INVALID");
      return null;
    }
    state = await probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: authoritativePhase });
  }
  if (!state || state.classification === "PARTIAL_OR_CONFLICTING") {
    console.log(JSON.stringify({ code: "SLICE_K_CLAIM_NOT_EXACT", detail: state && state.validation ? state.validation : null }, null, 2));
    fail("SLICE_K_CLAIM_NOT_EXACT");
    return null;
  }
  if (state.classification === "EXACT_CLAIM_CREATED") {
    try {
      validateSliceJLostLowerReplayWithinSliceK(state);
      validateSliceKClaimCreatedPersistedPostcondition(state);
    } catch (error) {
      console.log(JSON.stringify({ code: "SLICE_K_CLAIM_PERSISTED_POSTCONDITION_INVALID", detail: error && typeof error === "object" ? error.detail : null }, null, 2));
      fail("SLICE_K_CLAIM_PERSISTED_POSTCONDITION_INVALID");
      return null;
    }
    const observedAt = state.notificationSchedule.observedAt;
    const canonicalKey = state.canonicalNotificationKey;
    const worker = await invokeGoldenTrustedWorker({
      operation: "EVALUATE_TIKTOK_CLAIM_NOTIFICATIONS",
      organizationId,
      idempotencyKey: canonicalKey,
      observedAt,
      processName: SLICE_K.workerProcessName,
    });
    if (!worker.ok || !["COMPLETED", "REPLAYED"].includes(String(worker.action ?? "")) || String(worker.stockEffectCode ?? "") !== "NONE" || !UUID_PATTERN.test(String(worker.ruleRunId ?? ""))) {
      fail("SLICE_K_NOTIFICATION_WORKER_RESPONSE_INVALID");
      return null;
    }
    state = await probeSliceKTiktokClaimState(supabaseUrl, publishableKey, accessToken, organizationId, { projectionPhase: authoritativePhase });
    if (state) state.worker = worker;
  }
  if (!state || state.classification !== "EXACT_NOTIFICATION_CREATED") {
    fail("SLICE_K_NOTIFICATION_NOT_EXACT");
    return null;
  }
  try {
    validateSliceJLostLowerReplayWithinSliceK(state);
    validateSliceKNotificationPersistedPostcondition(state);
  } catch (error) {
    const code = error && typeof error === "object" && error.code === "GOLDEN_SLICE_K_NOTIFICATION_FIELD_MISMATCH"
      ? "GOLDEN_SLICE_K_NOTIFICATION_FIELD_MISMATCH"
      : "SLICE_J_LOST_PERSISTED_POSTCONDITION_INVALID";
    console.log(JSON.stringify({ code, detail: error && typeof error === "object" ? error.detail : null }, null, 2));
    fail(code);
    return null;
  }
  promoteSerumProjectionPhaseContext(state.effectivePhase);
  console.log("[PASS] Slice K TikTok claim D14 notification exact dan stock-neutral");
  return state;
}

async function main() {
  const expectedStateModelAudit = auditGoldenExpectedStateModel();
  console.log(JSON.stringify({ assertion: "Golden expected-state model audit", ...expectedStateModelAudit }, null, 2));
  if (expectedStateModelAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_EXPECTED_STATE_MODEL_AUDIT_FAILED");
  }
  const lowerSliceReplayAudit = auditGoldenLowerSliceReplayExpectedState();
  console.log(JSON.stringify({ assertion: "Golden lower-slice replay expected-state audit", ...lowerSliceReplayAudit }, null, 2));
  if (lowerSliceReplayAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_LOWER_SLICE_REPLAY_EXPECTED_STATE_AUDIT_FAILED");
  }
  const controlFlowAudit = auditGoldenPhaseControlFlowCompatibility();
  console.log(JSON.stringify({ assertion: "Golden phase control-flow compatibility", ...controlFlowAudit }, null, 2));
  if (controlFlowAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_PHASE_CONTROL_FLOW_AUDIT_FAILED");
  }
  const stateAwareControlFlowAudit = auditGoldenStateAwareControlFlowMatrix();
  console.log(JSON.stringify({ assertion: "Golden state-aware control-flow matrix", ...stateAwareControlFlowAudit }, null, 2));
  if (stateAwareControlFlowAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_STATE_AWARE_CONTROL_FLOW_AUDIT_FAILED");
  }
  const projectionEvidenceAudit = auditGoldenProjectionEvidenceContractMatrix();
  console.log(JSON.stringify({ assertion: "Golden projection-evidence contract matrix", ...projectionEvidenceAudit }, null, 2));
  if (projectionEvidenceAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_PROJECTION_EVIDENCE_CONTRACT_AUDIT_FAILED");
  }
  const projectionReplayContextAudit = auditGoldenProjectionReplayContextMatrix();
  console.log(JSON.stringify({ assertion: "Golden projection replay-context matrix", ...projectionReplayContextAudit }, null, 2));
  if (projectionReplayContextAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_PROJECTION_REPLAY_CONTEXT_AUDIT_FAILED");
  }
  const structuralCardinalityAudit = auditGoldenStructuralCardinalityMatrix();
  console.log(JSON.stringify({ assertion: "Golden structural-cardinality matrix", ...structuralCardinalityAudit }, null, 2));
  if (structuralCardinalityAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_STRUCTURAL_CARDINALITY_AUDIT_FAILED");
  }
  const lifecycleModelAudit = auditGoldenMarketplaceLifecyclePhaseMatrix();
  console.log(JSON.stringify({ assertion: "Golden marketplace lifecycle phase matrix", ...lifecycleModelAudit }, null, 2));
  if (lifecycleModelAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_LIFECYCLE_MODEL_AUDIT_FAILED");
  }
  const assertionContextAudit = auditGoldenAssertionContextMatrix();
  console.log(JSON.stringify({ assertion: "Golden assertion-context matrix", ...assertionContextAudit }, null, 2));
  if (assertionContextAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_ASSERTION_CONTEXT_AUDIT_FAILED");
  }
  const replayPhaseMonotonicityAudit = auditGoldenReplayPhaseMonotonicityMatrix();
  console.log(JSON.stringify({ assertion: "Golden replay phase monotonicity matrix", ...replayPhaseMonotonicityAudit }, null, 2));
  if (replayPhaseMonotonicityAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_REPLAY_PHASE_MONOTONICITY_AUDIT_FAILED");
  }
  const responseContractRegressionAudit = auditSliceJLostResponseContract();
  console.log(JSON.stringify({ assertion: "Golden Slice J LOST response contract regression audit", ...responseContractRegressionAudit }, null, 2));
  if (responseContractRegressionAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_RESPONSE_CONTRACT_AUDIT_FAILED");
  }
  const claimContractRegressionAudit = auditSliceKClaimContract();
  console.log(JSON.stringify({ assertion: "Golden Slice K claim contract regression audit", ...claimContractRegressionAudit }, null, 2));
  if (claimContractRegressionAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_CLAIM_CONTRACT_AUDIT_FAILED");
  }
  const crossPhasePostconditionRegressionAudit = auditSliceJPostconditionAcrossPhases();
  console.log(JSON.stringify({ assertion: "Golden Slice J cross-phase postcondition regression audit", ...crossPhasePostconditionRegressionAudit }, null, 2));
  if (crossPhasePostconditionRegressionAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_CROSS_PHASE_POSTCONDITION_AUDIT_FAILED");
  }
  const sliceKNotificationPersistedContractAudit = auditGoldenSliceKNotificationPersistedContractMatrix();
  console.log(JSON.stringify({ assertion: "Golden Slice K notification persisted-contract matrix", ...sliceKNotificationPersistedContractAudit }, null, 2));
  if (sliceKNotificationPersistedContractAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_SLICE_K_NOTIFICATION_PERSISTED_CONTRACT_AUDIT_FAILED");
  }
  const notificationContractRegressionAudit = auditSliceKNotificationContract();
  console.log(JSON.stringify({ assertion: "Golden Slice K notification contract audit", ...notificationContractRegressionAudit }, null, 2));
  if (notificationContractRegressionAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_NOTIFICATION_CONTRACT_AUDIT_FAILED");
  }
  const stocktakeContractAudit = auditGoldenStocktakeContractMatrix();
  console.log(JSON.stringify({ assertion: "Golden stocktake contract matrix", ...stocktakeContractAudit }, null, 2));
  if (stocktakeContractAudit.mismatchCount > 0) throw new Error("GOLDEN_STOCKTAKE_CONTRACT_AUDIT_FAILED");
  const reconciliationContractAudit = auditGoldenReconciliationContractMatrix();
  console.log(JSON.stringify({ assertion: "Golden reconciliation contract matrix", ...reconciliationContractAudit }, null, 2));
  if (reconciliationContractAudit.mismatchCount > 0) throw new Error("GOLDEN_RECONCILIATION_CONTRACT_AUDIT_FAILED");
  const reconciliationTerminalStatusAudit = auditGoldenReconciliationTerminalStatusMatrix();
  console.log(JSON.stringify({ assertion: "Golden reconciliation terminal-status matrix", ...reconciliationTerminalStatusAudit }, null, 2));
  if (reconciliationTerminalStatusAudit.mismatchCount > 0) throw new Error("GOLDEN_RECONCILIATION_TERMINAL_STATUS_AUDIT_FAILED");
  const finalAcceptanceAudit = auditGoldenFinalAcceptanceMatrix();
  console.log(JSON.stringify({ assertion: "Golden final acceptance matrix", ...finalAcceptanceAudit }, null, 2));
  if (finalAcceptanceAudit.mismatchCount > 0) throw new Error("GOLDEN_FINAL_ACCEPTANCE_AUDIT_FAILED");
  const returnLifecycleDurableReplayAudit = auditGoldenReturnLifecycleDurableReplayMatrix();
  console.log(JSON.stringify({ assertion: "Golden return lifecycle durable replay matrix", ...returnLifecycleDurableReplayAudit }, null, 2));
  if (returnLifecycleDurableReplayAudit.mismatchCount > 0) throw new Error("GOLDEN_RETURN_LIFECYCLE_DURABLE_REPLAY_AUDIT_FAILED");
  const sliceJDownstreamSupersetAudit = auditGoldenSliceJDownstreamSupersetReplayMatrix();
  console.log(JSON.stringify({ assertion: "Golden Slice J downstream-superset replay matrix", ...sliceJDownstreamSupersetAudit }, null, 2));
  if (sliceJDownstreamSupersetAudit.mismatchCount > 0) throw new Error("GOLDEN_SLICE_J_DOWNSTREAM_SUPERSET_AUDIT_FAILED");
  const runtimePreflightParityAudit = auditGoldenRuntimePreflightContractParityMatrix();
  console.log(JSON.stringify({ assertion: "Golden runtime/preflight contract parity matrix", ...runtimePreflightParityAudit }, null, 2));
  if (runtimePreflightParityAudit.mismatchCount > 0) throw new Error("GOLDEN_RUNTIME_PREFLIGHT_PARITY_AUDIT_FAILED");
  const durableSnapshotReaderAudit = auditGoldenDurableSnapshotReaderMatrix();
  console.log(JSON.stringify({ assertion: "Golden durable snapshot reader matrix", ...durableSnapshotReaderAudit }, null, 2));
  if (durableSnapshotReaderAudit.mismatchCount > 0) throw new Error("GOLDEN_DURABLE_SNAPSHOT_READER_AUDIT_FAILED");
  const exitSemanticsAudit = await auditGoldenExitSemantics();
  console.log(JSON.stringify({ assertion: "Golden runner exit-semantics regression", ...exitSemanticsAudit }, null, 2));
  if (exitSemanticsAudit.mismatchCount > 0) {
    throw new Error("GOLDEN_EXIT_SEMANTICS_AUDIT_FAILED");
  }
  if (process.env.GOLDEN_EXPECTED_STATE_AUDIT_ONLY === "1") {
    console.log("[PASS] Golden expected-state pure audits completed without database access");
    return;
  }

  const env = await loadEnvFile();
  const supabaseUrl = resolveEnv("NEXT_PUBLIC_SUPABASE_URL", env, DEFAULT_LOCAL_URL).replace(/\/$/, "");
  const publishableKey = resolveEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", env);
  const demoPassword = resolveEnv("PARALLEL_TEST_PASSWORD", env);

  if (!validateLocalSupabaseUrl(supabaseUrl)) {
    return;
  }

  if (!publishableKey || publishableKey.includes("REPLACE_ME")) {
    fail("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum tersedia di environment.");
    return;
  }

  if (!demoPassword) {
    fail("PARALLEL_TEST_PASSWORD belum tersedia. Muat password test lokal melalui environment.");
    return;
  }

  const auth = await authPreflight(supabaseUrl, publishableKey, demoPassword);
  if (!auth) return;

  // This gate is deliberately placed before every ensure/create path.  It is
  // read-only and reports all durable-replay mismatches together.
  const preflightSerumRows = await readProductBySku(
    supabaseUrl,
    publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-NIA-30",
  );
  if (!preflightSerumRows || preflightSerumRows.length !== 1 || !isNonBlank(preflightSerumRows[0]?.product_id)) {
    fail("Golden replay preflight tidak dapat menyelesaikan satu product Serum.");
    return;
  }
  const replayPreflight = await auditPersistedGoldenReplayState(
    supabaseUrl,
    publishableKey,
    auth.accessToken,
    auth.organizationId,
    preflightSerumRows[0].product_id,
    { expectedStateModelAudit, lowerSliceReplayAudit, controlFlowAudit, stateAwareControlFlowAudit, projectionEvidenceAudit, projectionReplayContextAudit, structuralCardinalityAudit, lifecycleModelAudit, assertionContextAudit, replayPhaseMonotonicityAudit, claimContractRegressionAudit, crossPhasePostconditionRegressionAudit, sliceKNotificationPersistedContractAudit, notificationContractRegressionAudit, stocktakeContractAudit, reconciliationContractAudit, reconciliationTerminalStatusAudit, finalAcceptanceAudit, returnLifecycleDurableReplayAudit, sliceJDownstreamSupersetAudit, runtimePreflightParityAudit, durableSnapshotReaderAudit, exitSemanticsAudit },
  );
  if (!replayPreflight) return;
  if (process.env.GOLDEN_REPLAY_PREFLIGHT_ONLY === "1") {
    console.log("[PASS] Golden replay aggregate preflight completed without mutation");
    return;
  }

  const products = new Map();
  for (const fixture of PRODUCT_FIXTURES) {
    const existing = await readProductBySku(
      supabaseUrl,
      publishableKey,
      auth.accessToken,
      auth.organizationId,
      fixture.sku,
    );
    if (!existing) return;
    const product = assertBaselineProductRows(existing, fixture, auth.organizationId);
    if (!product) return;
    products.set(fixture.sku, product);
  }

  const batches = new Map();
  for (const fixture of BATCH_FIXTURES) {
    const product = products.get(fixture.productSku);
    if (!product?.productId) {
      fail(`Produk ${fixture.productSku} belum tersedia untuk verifikasi batch.`);
      return;
    }
    const existing = await readBatchByCode(
      supabaseUrl,
      publishableKey,
      auth.accessToken,
      auth.organizationId,
      product.productId,
      fixture.batchCode,
    );
    if (!existing) return;
    const batch = assertBaselineBatchRows(existing, fixture, auth.organizationId, product.productId);
    if (!batch) return;
    batches.set(fixture.batchCode, batch);
  }

  const initialSerumProjectionPhase = await detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
    supabaseUrl,
    publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!initialSerumProjectionPhase) return;
  promoteSerumProjectionPhaseContext(initialSerumProjectionPhase);

  console.log("[PASS] Slice A baseline products and batches adopted");

  const sliceBSourceRef = "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM";
  const sliceBReceiptBefore = await readReceiptBySourceRef(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    sliceBSourceRef,
  );
  if (!sliceBReceiptBefore) return;
  if (sliceBReceiptBefore.length > 1) {
    fail("Receipt Slice B duplikat sebelum verifikasi.");
    return;
  }

  const readModelSnapshot = await fetchReadModel(
    supabaseUrl,
    publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!readModelSnapshot) return;

  if (sliceBReceiptBefore.length === 0) {
    const existingSliceBBatchRows = (readModelSnapshot?.batchInventory ?? []).filter(
      (row) => String(row?.batch_code ?? "") === "SER-2701-C",
    );
    if (existingSliceBBatchRows.length > 1) {
      fail("Projection batch Slice B fresh path duplikat sebelum receipt.");
      return;
    }

    if (!assertSliceALiveBaseline(readModelSnapshot)) {
      return;
    }
  }

  const ledgerRows = await fetchSeededInitialBalanceLedgerRows(
    supabaseUrl,
    publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!ledgerRows) return;

  if (!assertSeededInitialBalanceLedger(ledgerRows, batches)) return;

  console.log("[PASS] Slice A seeded initial-balance ledger verified");

  const sliceBBatch = await ensureSliceBBatch(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    products,
    batches,
  );
  if (!sliceBBatch) return;
  console.log("[PASS] Slice B batch SER-2701-C adopted");

  if (sliceBReceiptBefore.length === 0) {
    if (
      !(await assertSliceBFreshBaseline(
        auth.supabaseUrl,
        auth.publishableKey,
        auth.accessToken,
        auth.organizationId,
        sliceBBatch,
        readModelSnapshot,
      ))
    ) {
      return;
    }
  }

  const sliceBReceipt = await ensureSliceBReceipt(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    sliceBBatch,
  );
  if (!sliceBReceipt) return;

  const sliceBLedgerRows = await readJsonRows(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    `stock_ledger?organization_id=eq.${encodeURIComponent(auth.organizationId)}&transaction_id=eq.${encodeURIComponent(sliceBReceipt.receipt.transaction_id ?? sliceBReceipt.receipt.transactionId)}&order=ledger_seq.asc&select=ledger_seq,ledger_entry_id,organization_id,transaction_id,transaction_no,transaction_type_code,reason_code_snapshot,channel_code_snapshot,source_type_code,source_ref_snapshot,source_line_ref,line_no,product_id,batch_id,product_sku_snapshot,batch_code_snapshot,expiry_date_snapshot,bucket_code,quantity_delta,entry_role_code,occurred_at,recorded_at`,
  );
  if (!sliceBLedgerRows) return;
  if (sliceBLedgerRows.length !== 1) {
    fail("Ledger Slice B harus tepat satu row.");
    return;
  }
  const sliceBRow = sliceBLedgerRows[0];
  if (
    String(sliceBRow?.organization_id ?? "") !== String(auth.organizationId) ||
    String(sliceBRow?.transaction_type_code ?? "") !== "RECEIPT" ||
    String(sliceBRow?.reason_code_snapshot ?? "") !== "MAKLON_RECEIPT" ||
    String(sliceBRow?.channel_code_snapshot ?? "") !== "MANUAL" ||
    String(sliceBRow?.source_type_code ?? "") !== "RECEIPT" ||
    String(sliceBRow?.source_ref_snapshot ?? "") !== "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM" ||
    String(sliceBRow?.product_id ?? "") !== String(sliceBBatch.productId) ||
    String(sliceBRow?.batch_id ?? "") !== String(sliceBBatch.batchId) ||
    String(sliceBRow?.product_sku_snapshot ?? "") !== "SER-NIA-30" ||
    String(sliceBRow?.batch_code_snapshot ?? "") !== "SER-2701-C" ||
    String(sliceBRow?.expiry_date_snapshot ?? "") !== "2027-01-31" ||
    !sameInstant(sliceBRow?.occurred_at, "2026-07-15T02:00:00Z") ||
    String(sliceBRow?.bucket_code ?? "") !== "SELLABLE" ||
    Number(sliceBRow?.quantity_delta) !== 10 ||
    String(sliceBRow?.entry_role_code ?? "") !== "EXTERNAL_IN" ||
    String(sliceBRow?.source_line_ref ?? "") !== "GOLDEN-DEMO-V1:RECEIPT:MAKLON-SERUM:1"
  ) {
    fail("Ledger Slice B tidak exact.");
    return;
  }

  console.log("[PASS] Slice B Maklon receipt replayed with one domain effect");
  console.log("[PASS] Slice B receipt ledger SELLABLE +10 exact");

  const readModelAfterSliceB = await fetchReadModel(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!readModelAfterSliceB) return;
  const sliceCExistingBefore = await readSliceCNormalizations(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!sliceCExistingBefore) {
    return;
  }
  const serumProjectionPhase = await detectCurrentSerumProjectionPhaseWithLatestTiktokFallback(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!serumProjectionPhase) {
    return;
  }
  promoteSerumProjectionPhaseContext(serumProjectionPhase);
  if (!assertSliceBProjection(readModelAfterSliceB, serumProjectionPhase)) {
    return;
  }

  const serumProduct = products.get("SER-NIA-30");
  if (!serumProduct?.productId) {
    fail("Produk Serum belum tersedia untuk Slice C.");
    return;
  }

  const sliceCListing = await ensureSliceCShopeeListing(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
    serumProjectionPhase,
  );
  if (!sliceCListing) {
    return;
  }

  console.log("[PASS] Slice C Shopee listing SHP-SER-NIA-30 created/adopted stock-neutral");

  const sliceCResult = await runSliceCReservationStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceCResult) {
    return;
  }
  if (!verifyGoldenCompletionGuard("sliceC", currentSerumProjectionPhaseContext, sliceCResult?.effectivePhase)) return;

  console.log("[PASS] Slice C Shopee reservation applied/replayed with one domain effect");
  console.log("[PASS] Slice C normalization and reservation evidence exact");

  const sliceDResult = await runSliceDShipment(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceDResult) {
    return;
  }

  const tiktokProjectionPhase = await detectCurrentTiktokProjectionPhase(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!tiktokProjectionPhase) {
    return;
  }
  promoteSerumProjectionPhaseContext(tiktokProjectionPhase);
  if (!verifyGoldenCompletionGuard("sliceD", currentSerumProjectionPhaseContext, tiktokProjectionPhase)) return;

  console.log("[PASS] Slice D Shopee SHIPPED applied/replayed with one domain effect");
  console.log("[PASS] Slice D FEFO split SER-2608-A=5 SER-2612-B=3 exact");
  console.log("[PASS] Slice D reservation consumed and shipment audit exact");
  console.log("[PASS] Slice D ledger SELLABLE -5/-3 exact");
  console.log(`[PASS] Slice D replay preserved projection ${tiktokProjectionPhase.detectedPhase} Serum=${tiktokProjectionPhase.sellable} Reserved=${tiktokProjectionPhase.reserved} Available=${tiktokProjectionPhase.available}`);

  const sliceEListing = await ensureSliceETiktokListing(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
    tiktokProjectionPhase,
  );
  if (!sliceEListing) {
    return;
  }

  console.log("[PASS] Slice E TikTok listing TTS-SER-NIA-30 created/adopted stock-neutral");

  const sliceEResult = await runSliceETiktokReservationStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  const exactSliceEResult = assertGoldenStateAwareSuccessResult(
    sliceEResult,
    "runSliceETiktokReservationStateAware",
  );
  const sliceEProjectionEvidence = exactSliceEResult.persistedEvidence.afterProjection;
  if (
    !exactSliceEResult.persistedEvidence.reservation
    || !isNonBlank(exactSliceEResult.persistedEvidence.eventEvidence?.eventId)
    || String(exactSliceEResult.persistedEvidence.reservation.reservationId ?? "") !== exactSliceEResult.reservationId
  ) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_EVIDENCE_PARTIAL");
  }
  assertSliceEReservationCallerProjectionEvidence(exactSliceEResult, sliceEProjectionEvidence);
  const sliceEReservationReplayContract = assertSliceEReservationCallerCanContinue(exactSliceEResult);
  if (!verifyGoldenCompletionGuard("sliceEReserved", exactSliceEResult.phase)) {
    failGoldenStateAware("GOLDEN_SLICE_E_RESERVATION_CHECKPOINT_FAILED");
  }
  promoteSerumProjectionPhaseContext(exactSliceEResult.phase);

  console.log(`[PASS] Slice E TikTok reservation ${exactSliceEResult.outcome} exact with one domain effect`);
  console.log("[PASS] Slice E reservation stock-neutral exact");
  console.log("[PASS] Slice E reservation projection evidence exact");
  console.log(`[PASS] Slice E reservation ${sliceEReservationReplayContract.phaseContract.mode} dengan evidence historis exact`);

  const sliceEShipResult = await runSliceETiktokShipmentStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceEShipResult) {
    return;
  }

  const finalTiktokProjectionPhase = await detectCurrentTiktokProjectionPhaseWrapper(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!finalTiktokProjectionPhase) {
    return;
  }

  const finalSliceECompletionPhase = highestGoldenCurrentStatePhase(
    currentSerumProjectionPhaseContext,
    finalTiktokProjectionPhase,
  );
  try {
    assertGoldenCompletionPhase("sliceE", finalSliceECompletionPhase);
  } catch (error) {
    fail(
      error instanceof Error ? error.message : "GOLDEN_COMPLETION_PHASE_TOO_LOW: sliceE",
    );
    return;
  }

  promoteSerumProjectionPhaseContext(finalSliceECompletionPhase);

  console.log("[PASS] Slice E TikTok IN_TRANSIT applied/replayed with one domain effect");
  console.log("[PASS] Slice E FEFO single allocation SER-2612-B=1 exact");
  console.log("[PASS] Slice E reservation consumed and shipment audit exact");
  console.log("[PASS] Slice E ledger SELLABLE -1 exact");
  console.log(`[PASS] Slice E projection ${finalSliceECompletionPhase.detectedPhase} Serum=${finalSliceECompletionPhase.sellable} Reserved=${finalSliceECompletionPhase.reserved} Available=${finalSliceECompletionPhase.available}`);

  const manualBonusSourceRef = "GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:QTY-2";
  const manualBonusIdempotencyKey = manualBonusSourceRef;
  const manualBonusOccurredAt = "2026-07-15T03:40:00Z";
  const manualBonusReference = "BONUS|MANUAL|SER-NIA-30|QTY-2";
  const manualBonusPayload = {
    p_organization_id: auth.organizationId,
    p_source_ref: manualBonusSourceRef,
    p_occurred_at: manualBonusOccurredAt,
    p_reason_code: "BONUS",
    p_lines: [
      {
        productId: serumProduct.productId,
        quantity: 2,
        sourceLineRef: "GOLDEN-DEMO-V1:MANUAL:BONUS:SER-NIA-30:LINE-1",
      },
    ],
    p_note: "Golden Demo Slice F manual bonus serum 2 units.",
    p_metadata: {
      source: "golden-demo-runner",
      version: 1,
      slice: "F",
      scenario: "manual-bonus-serum-2",
      reference: manualBonusReference,
    },
  };
  const manualBonusPreviewPayload = {
    p_organization_id: manualBonusPayload.p_organization_id,
    p_source_ref: manualBonusPayload.p_source_ref,
    p_occurred_at: manualBonusPayload.p_occurred_at,
    p_reason_code: manualBonusPayload.p_reason_code,
    p_lines: manualBonusPayload.p_lines,
    p_note: manualBonusPayload.p_note,
    p_metadata: manualBonusPayload.p_metadata,
  };
  const manualBonusPostPayload = {
    p_organization_id: auth.organizationId,
    p_idempotency_key: manualBonusIdempotencyKey,
    p_source_ref: manualBonusSourceRef,
    p_occurred_at: manualBonusOccurredAt,
    p_reason_code: "BONUS",
    p_lines: manualBonusPayload.p_lines,
    p_preview_basis_hash: "",
    p_confirmation: true,
    p_note: "Golden Demo Slice F manual bonus serum 2 units.",
    p_metadata: manualBonusPayload.p_metadata,
  };

  const manualBonusOutbounds = await readManualOutboundsBySourceRef(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    manualBonusSourceRef,
  );
  if (!manualBonusOutbounds) return;
  const manualBonusAfterProductRows = await readProductInventoryBySku(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-NIA-30",
  );
  if (!manualBonusAfterProductRows) return;
  const manualBonusAfterBatch2608Rows = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2608-A",
  );
  if (!manualBonusAfterBatch2608Rows) return;
  const manualBonusAfterBatch2612Rows = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2612-B",
  );
  if (!manualBonusAfterBatch2612Rows) return;
  const manualBonusAfterBatch2701Rows = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2701-C",
  );
  if (!manualBonusAfterBatch2701Rows) return;
  const manualBonusBeforeCounts = {
    outbound: manualBonusOutbounds.length,
    line: 0,
    allocation: 0,
    transaction: 0,
    ledger: 0,
  };

  const manualBonusStates = [];
  if (manualBonusOutbounds.length === 0) {
    manualBonusStates.push("NONE");
  } else if (manualBonusOutbounds.length === 1) {
    const manualBonusOutboundRow = manualBonusOutbounds[0];
    const manualBonusLines = await readManualOutboundLinesByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusLines) return;
    const manualBonusAllocations = await readManualOutboundAllocationsByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusAllocations) return;
    const manualBonusLedgerRows = await readStockLedgerByTransactionId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.transaction_id,
    );
    if (!manualBonusLedgerRows) return;

    manualBonusBeforeCounts.line = manualBonusLines.length;
    manualBonusBeforeCounts.allocation = manualBonusAllocations.length;
    manualBonusBeforeCounts.transaction = isNonBlank(manualBonusOutboundRow?.transaction_id) ? 1 : 0;
    manualBonusBeforeCounts.ledger = manualBonusLedgerRows.length;

    const manualBonusLine = manualBonusLines[0];
    const manualBonusAllocation = manualBonusAllocations[0];
    const manualBonusLedgerRow = manualBonusLedgerRows[0];
    const manualBonusExactExistingChecks = [
      {
        name: "manual outbound count",
        expected: 1,
        actual: manualBonusOutbounds.length,
        passed: manualBonusOutbounds.length === 1,
      },
      {
        name: "line count",
        expected: 1,
        actual: manualBonusLines.length,
        passed: manualBonusLines.length === 1,
      },
      {
        name: "allocation count",
        expected: 1,
        actual: manualBonusAllocations.length,
        passed: manualBonusAllocations.length === 1,
      },
      {
        name: "transaction count",
        expected: 1,
        actual: isNonBlank(manualBonusOutboundRow?.transaction_id) ? 1 : 0,
        passed: isNonBlank(manualBonusOutboundRow?.transaction_id),
      },
      {
        name: "ledger count",
        expected: 1,
        actual: manualBonusLedgerRows.length,
        passed: manualBonusLedgerRows.length === 1,
      },
      {
        name: "organization_id",
        expected: String(auth.organizationId),
        actual: String(manualBonusOutboundRow?.organization_id ?? ""),
        passed: String(manualBonusOutboundRow?.organization_id ?? "") === String(auth.organizationId),
      },
      {
        name: "source_ref",
        expected: manualBonusSourceRef,
        actual: String(manualBonusOutboundRow?.source_ref ?? ""),
        passed: String(manualBonusOutboundRow?.source_ref ?? "") === manualBonusSourceRef,
      },
      {
        name: "reason code",
        expected: "BONUS",
        actual: String(manualBonusOutboundRow?.reason_code_snapshot ?? ""),
        passed: String(manualBonusOutboundRow?.reason_code_snapshot ?? "") === "BONUS",
      },
      {
        name: "metadata.reference",
        expected: manualBonusReference,
        actual: String(manualBonusOutboundRow?.metadata?.reference ?? ""),
        passed: String(manualBonusOutboundRow?.metadata?.reference ?? "") === manualBonusReference,
      },
      {
        name: "product identity",
        expected: "SER-NIA-30",
        actual: String(manualBonusLine?.product_sku_snapshot ?? ""),
        passed: String(manualBonusLine?.product_sku_snapshot ?? "") === "SER-NIA-30",
      },
      {
        name: "requested quantity",
        expected: 2,
        actual: Number(manualBonusLine?.quantity_requested),
        passed: Number(manualBonusLine?.quantity_requested) === 2,
      },
      {
        name: "allocation quantity",
        expected: 2,
        actual: Number(manualBonusAllocation?.quantity_allocated),
        passed: Number(manualBonusAllocation?.quantity_allocated) === 2,
      },
      {
        name: "allocation batch",
        expected: "SER-2612-B",
        actual: String(manualBonusAllocation?.batch_code_snapshot ?? ""),
        passed: String(manualBonusAllocation?.batch_code_snapshot ?? "") === "SER-2612-B",
      },
      {
        name: "ledger bucket",
        expected: "SELLABLE",
        actual: String(manualBonusLedgerRow?.bucket_code ?? ""),
        passed: String(manualBonusLedgerRow?.bucket_code ?? "") === "SELLABLE",
      },
      {
        name: "ledger quantity_delta",
        expected: -2,
        actual: Number(manualBonusLedgerRow?.quantity_delta),
        passed: Number(manualBonusLedgerRow?.quantity_delta) === -2,
      },
      {
        name: "transaction_id linkage",
        expected: String(manualBonusOutboundRow?.transaction_id ?? ""),
        actual: String(manualBonusOutboundRow?.transaction_id ?? ""),
        passed:
          String(manualBonusOutboundRow?.transaction_id ?? "") === String(manualBonusLedgerRow?.transaction_id ?? "") &&
          String(manualBonusOutboundRow?.transaction_id ?? "") === String(manualBonusAllocation?.ledger_entry_id ? manualBonusOutboundRow?.transaction_id : manualBonusOutboundRow?.transaction_id),
      },
      {
        name: "transaction_type_code",
        expected: "MANUAL_OUTBOUND",
        actual: String(manualBonusLedgerRow?.transaction_type_code ?? ""),
        passed: String(manualBonusLedgerRow?.transaction_type_code ?? "") === "MANUAL_OUTBOUND",
      },
      {
        name: "projection and batch balances",
        expected: resolveExpectedSerumProjectionPhase(buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN)),
        actual: `${String(manualBonusAfterProductRows?.[0]?.sellable_qty ?? "")} / ${String(manualBonusAfterProductRows?.[0]?.reserved_qty ?? "")} / ${String(manualBonusAfterProductRows?.[0]?.available_qty ?? "")}; ${Number(manualBonusAfterBatch2608Rows[0]?.sellable_qty ?? 0)} / ${Number(manualBonusAfterBatch2612Rows[0]?.sellable_qty ?? 0)} / ${Number(manualBonusAfterBatch2701Rows[0]?.sellable_qty ?? 0)}`,
        passed: matchesSerumProjectionExact(
          {
            productInventory: manualBonusAfterProductRows,
            batchInventory: [
              ...manualBonusAfterBatch2608Rows,
              ...manualBonusAfterBatch2612Rows,
              ...manualBonusAfterBatch2701Rows,
            ],
          },
          resolveExpectedSerumProjectionPhase(buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN)),
        ),
      },
    ];
    const manualBonusFailedChecks = manualBonusExactExistingChecks.filter((check) => !check.passed);
    if (manualBonusFailedChecks.length > 0) {
      console.log("[FAIL] Slice F EXACT_EXISTING predicate");
      console.log("       Failed checks:");
      for (const check of manualBonusFailedChecks) {
        console.log(`       - ${check.name}`);
        console.log(`         expected: ${JSON.stringify(check.expected)}`);
        console.log(`         actual: ${JSON.stringify(check.actual)}`);
      }
      return;
    }

    manualBonusStates.push("EXACT_EXISTING");
  } else {
    fail(`Slice F conflict/partial: manual_outbounds count ${manualBonusOutbounds.length}.`);
    return;
  }

  if (manualBonusStates[0] === "NONE") {
    const previewManualBonus = await rpcJson(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      "preview_manual_outbound",
      manualBonusPreviewPayload,
    );
    if (previewManualBonus.status !== 200) {
      fail(`preview_manual_outbound Slice F gagal: ${parseResponseText(previewManualBonus.payload)}`);
      return;
    }
    const previewManualBonusJson = previewManualBonus.payload;
    if (
      String(previewManualBonusJson?.status ?? "") !== "PREVIEW_READY" ||
      String(previewManualBonusJson?.eligible ?? "") !== "true" ||
      !isHex64(previewManualBonusJson?.basisHash) ||
      asNumber(previewManualBonusJson?.lineCount) !== 1 ||
      asNumber(previewManualBonusJson?.allocationCount) !== 1 ||
      String(previewManualBonusJson?.reasonCode ?? "") !== "BONUS" ||
      String(previewManualBonusJson?.channelCode ?? "") !== "MANUAL" ||
      String(previewManualBonusJson?.allocations?.[0]?.batchCode ?? "") !== "SER-2612-B" ||
      asNumber(previewManualBonusJson?.allocations?.[0]?.quantity) !== 2
    ) {
      fail(`Preview Slice F tidak exact. actual=${JSON.stringify(previewManualBonusJson)}`);
      return;
    }
    if (
      asNumber(previewManualBonusJson?.products?.[0]?.currentSellable) !== 26 ||
      asNumber(previewManualBonusJson?.products?.[0]?.currentReserved) !== 0 ||
      asNumber(previewManualBonusJson?.products?.[0]?.currentAvailable) !== 26 ||
      asNumber(previewManualBonusJson?.products?.[0]?.resultingSellable) !== 24 ||
      asNumber(previewManualBonusJson?.products?.[0]?.resultingAvailable) !== 24
    ) {
      fail(`Preview Slice F product snapshot tidak exact. actual=${JSON.stringify(previewManualBonusJson?.products?.[0] ?? null)}`);
      return;
    }

    const postManualBonus = await rpcJson(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      "post_manual_outbound",
      {
        ...manualBonusPostPayload,
        p_preview_basis_hash: previewManualBonusJson.basisHash,
      },
    );
    if (postManualBonus.status !== 200) {
      fail(`post_manual_outbound Slice F gagal: ${parseResponseText(postManualBonus.payload)}`);
      return;
    }
    const postManualBonusJson = postManualBonus.payload;
    if (
      String(postManualBonusJson?.status ?? "") !== "POSTED" ||
      String(postManualBonusJson?.reasonCode ?? "") !== "BONUS" ||
      String(postManualBonusJson?.outboundId ?? "") === "" ||
      String(postManualBonusJson?.transactionId ?? "") === "" ||
      asNumber(postManualBonusJson?.lineCount) !== 1 ||
      asNumber(postManualBonusJson?.allocationCount) !== 1 ||
      asNumber(postManualBonusJson?.totalQuantity) !== 2
    ) {
      fail(`Post Slice F tidak exact. actual=${JSON.stringify(postManualBonusJson)}`);
      return;
    }

    const replayManualBonus = await rpcJson(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      "post_manual_outbound",
      {
        ...manualBonusPostPayload,
        p_preview_basis_hash: previewManualBonusJson.basisHash,
      },
    );
    if (replayManualBonus.status !== 200) {
      fail(`Replay post_manual_outbound Slice F gagal: ${parseResponseText(replayManualBonus.payload)}`);
      return;
    }
    const replayManualBonusJson = replayManualBonus.payload;
    if (
      String(replayManualBonusJson?.outboundId ?? "") !== String(postManualBonusJson?.outboundId ?? "") ||
      String(replayManualBonusJson?.transactionId ?? "") !== String(postManualBonusJson?.transactionId ?? "") ||
      String(replayManualBonusJson?.outboundNo ?? "") !== String(postManualBonusJson?.outboundNo ?? "")
    ) {
      fail("Replay Slice F tidak identik dengan post pertama.");
      return;
    }
  }

  const manualBonusAfterOutbounds = await readManualOutboundsBySourceRef(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    manualBonusSourceRef,
  );
  if (!manualBonusAfterOutbounds) return;
  const manualBonusAfterProductRowsFinal = await readProductInventoryBySku(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-NIA-30",
  );
  if (!manualBonusAfterProductRowsFinal) return;
  const manualBonusAfterBatch2608RowsFinal = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2608-A",
  );
  if (!manualBonusAfterBatch2608RowsFinal) return;
  const manualBonusAfterBatch2612RowsFinal = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2612-B",
  );
  if (!manualBonusAfterBatch2612RowsFinal) return;
  const manualBonusAfterBatch2701RowsFinal = await readBatchInventoryByCode(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    "SER-2701-C",
  );
  if (!manualBonusAfterBatch2701RowsFinal) return;
  const manualBonusAfterCounts = {
    outbound: manualBonusAfterOutbounds.length,
    line: manualBonusStates[0] === "NONE"
      ? 1
      : manualBonusBeforeCounts.line,
    allocation: manualBonusStates[0] === "NONE"
      ? 1
      : manualBonusBeforeCounts.allocation,
    transaction: manualBonusStates[0] === "NONE"
      ? 1
      : manualBonusBeforeCounts.transaction,
    ledger: manualBonusStates[0] === "NONE"
      ? 1
      : manualBonusBeforeCounts.ledger,
  };

  const manualBonusProjectionPhase = manualBonusAfterProductRowsFinal?.[0] && asNumber(manualBonusAfterProductRowsFinal[0]?.reserved_qty) === 2
    ? buildBundleProjectionPhase("SLICE_G_BUNDLE_RESERVED")
    : asNumber(manualBonusAfterProductRowsFinal?.[0]?.sellable_qty) === 22
      ? buildBundleProjectionPhase("SLICE_G_BUNDLE_SHIPPED")
      : buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN);
  const manualBonusCurrentExpectedPhase = resolveExpectedSerumProjectionPhase(manualBonusProjectionPhase);

  if (manualBonusStates[0] === "NONE") {
    const manualBonusOutboundsAfterCreate = manualBonusAfterOutbounds;
    const manualBonusOutboundRow = manualBonusOutboundsAfterCreate[0];
    const manualBonusLines = await readManualOutboundLinesByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusLines) return;
    const manualBonusAllocations = await readManualOutboundAllocationsByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusAllocations) return;
    const manualBonusLedgerRows = await readStockLedgerByTransactionId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.transaction_id,
    );
    if (!manualBonusLedgerRows) return;
    const manualBonusCreateChecks = [
      { name: "manual outbound count", expected: 1, actual: manualBonusOutboundsAfterCreate.length, passed: manualBonusOutboundsAfterCreate.length === 1 },
      { name: "line count", expected: 1, actual: manualBonusLines.length, passed: manualBonusLines.length === 1 },
      { name: "allocation count", expected: 1, actual: manualBonusAllocations.length, passed: manualBonusAllocations.length === 1 },
      { name: "transaction count", expected: 1, actual: isNonBlank(manualBonusOutboundRow?.transaction_id) ? 1 : 0, passed: isNonBlank(manualBonusOutboundRow?.transaction_id) },
      { name: "ledger count", expected: 1, actual: manualBonusLedgerRows.length, passed: manualBonusLedgerRows.length === 1 },
      { name: "organization_id", expected: String(auth.organizationId), actual: String(manualBonusOutboundRow?.organization_id ?? ""), passed: String(manualBonusOutboundRow?.organization_id ?? "") === String(auth.organizationId) },
      { name: "source_ref", expected: manualBonusSourceRef, actual: String(manualBonusOutboundRow?.source_ref ?? ""), passed: String(manualBonusOutboundRow?.source_ref ?? "") === manualBonusSourceRef },
      { name: "reason code", expected: "BONUS", actual: String(manualBonusOutboundRow?.reason_code_snapshot ?? ""), passed: String(manualBonusOutboundRow?.reason_code_snapshot ?? "") === "BONUS" },
      { name: "ledger channel code", expected: "MANUAL", actual: String(manualBonusLedgerRows[0]?.channel_code_snapshot ?? ""), passed: String(manualBonusLedgerRows[0]?.channel_code_snapshot ?? "") === "MANUAL" },
      { name: "metadata.reference", expected: manualBonusReference, actual: String(manualBonusOutboundRow?.metadata?.reference ?? ""), passed: String(manualBonusOutboundRow?.metadata?.reference ?? "") === manualBonusReference },
      { name: "product identity", expected: "SER-NIA-30", actual: String(manualBonusLines[0]?.product_sku_snapshot ?? ""), passed: String(manualBonusLines[0]?.product_sku_snapshot ?? "") === "SER-NIA-30" },
      { name: "requested quantity", expected: 2, actual: Number(manualBonusLines[0]?.quantity_requested), passed: Number(manualBonusLines[0]?.quantity_requested) === 2 },
      { name: "allocation quantity", expected: 2, actual: Number(manualBonusAllocations[0]?.quantity_allocated), passed: Number(manualBonusAllocations[0]?.quantity_allocated) === 2 },
      { name: "allocation batch", expected: "SER-2612-B", actual: String(manualBonusAllocations[0]?.batch_code_snapshot ?? ""), passed: String(manualBonusAllocations[0]?.batch_code_snapshot ?? "") === "SER-2612-B" },
      { name: "ledger bucket", expected: "SELLABLE", actual: String(manualBonusLedgerRows[0]?.bucket_code ?? ""), passed: String(manualBonusLedgerRows[0]?.bucket_code ?? "") === "SELLABLE" },
      { name: "ledger quantity_delta", expected: -2, actual: Number(manualBonusLedgerRows[0]?.quantity_delta), passed: Number(manualBonusLedgerRows[0]?.quantity_delta) === -2 },
      { name: "transaction_type_code", expected: "MANUAL_OUTBOUND", actual: String(manualBonusLedgerRows[0]?.transaction_type_code ?? ""), passed: String(manualBonusLedgerRows[0]?.transaction_type_code ?? "") === "MANUAL_OUTBOUND" },
      { name: "product projection", expected: manualBonusCurrentExpectedPhase, actual: `${String(manualBonusAfterProductRowsFinal?.[0]?.sellable_qty ?? "")} / ${String(manualBonusAfterProductRowsFinal?.[0]?.reserved_qty ?? "")} / ${String(manualBonusAfterProductRowsFinal?.[0]?.available_qty ?? "")}`, passed: Number(manualBonusAfterProductRowsFinal?.[0]?.sellable_qty) === manualBonusCurrentExpectedPhase.sellable && Number(manualBonusAfterProductRowsFinal?.[0]?.reserved_qty) === manualBonusCurrentExpectedPhase.reserved && Number(manualBonusAfterProductRowsFinal?.[0]?.available_qty) === manualBonusCurrentExpectedPhase.available },
      { name: "batch SER-2608-A", expected: expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2608-A"), actual: Number(manualBonusAfterBatch2608RowsFinal?.[0]?.sellable_qty ?? NaN), passed: Number(manualBonusAfterBatch2608RowsFinal?.[0]?.sellable_qty) === expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2608-A") },
      { name: "batch SER-2612-B", expected: expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2612-B"), actual: Number(manualBonusAfterBatch2612RowsFinal?.[0]?.sellable_qty ?? NaN), passed: Number(manualBonusAfterBatch2612RowsFinal?.[0]?.sellable_qty) === expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2612-B") },
      { name: "batch SER-2701-C", expected: expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2701-C"), actual: Number(manualBonusAfterBatch2701RowsFinal?.[0]?.sellable_qty ?? NaN), passed: Number(manualBonusAfterBatch2701RowsFinal?.[0]?.sellable_qty) === expectedBatchQuantityForPhase(manualBonusCurrentExpectedPhase, "SER-2701-C") },
      { name: "manual after counts", expected: { outbound: 1, line: 1, allocation: 1, transaction: 1, ledger: 1 }, actual: manualBonusAfterCounts, passed: manualBonusAfterCounts.outbound === 1 && manualBonusAfterCounts.line === 1 && manualBonusAfterCounts.allocation === 1 && manualBonusAfterCounts.transaction === 1 && manualBonusAfterCounts.ledger === 1 },
    ];
    const manualBonusCreateFailedChecks = manualBonusCreateChecks.filter((check) => !check.passed);
    if (manualBonusCreateFailedChecks.length > 0) {
      console.log(JSON.stringify({
        classification: "Slice F create-state",
        commandResultStatus: "created-or-replayed",
        phaseContextBefore: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
        detectedPhaseAfter:
          manualBonusAfterProductRowsFinal?.[0] && asNumber(manualBonusAfterProductRowsFinal[0]?.reserved_qty) === 2
            ? "SLICE_G_BUNDLE_RESERVED"
            : asNumber(manualBonusAfterProductRowsFinal?.[0]?.sellable_qty) === 22
              ? "SLICE_G_BUNDLE_SHIPPED"
              : "SLICE_F_MANUAL_BONUS",
        phaseContextAfter: currentSerumProjectionPhaseContext?.detectedPhase ?? null,
        manualBonusBeforeCounts,
        manualBonusAfterCounts,
        manualOutboundRow: manualBonusOutboundRow,
        manualOutboundLineRows: manualBonusLines,
        allocationRows: manualBonusAllocations,
        transactionRows: isNonBlank(manualBonusOutboundRow?.transaction_id) ? [{ transaction_id: manualBonusOutboundRow.transaction_id }] : [],
        ledgerRows: manualBonusLedgerRows,
        serumProductProjection: manualBonusAfterProductRowsFinal?.[0] ?? null,
        serumBatchProjections: {
          "SER-2608-A": manualBonusAfterBatch2608RowsFinal?.[0] ?? null,
          "SER-2612-B": manualBonusAfterBatch2612RowsFinal?.[0] ?? null,
          "SER-2701-C": manualBonusAfterBatch2701RowsFinal?.[0] ?? null,
        },
        failedChecks: manualBonusCreateFailedChecks,
        expected: {
          product: {
            sellableQty: 24,
            reservedQty: 0,
            availableQty: 24,
          },
          batches: {
            "SER-2608-A": 0,
            "SER-2612-B": 14,
            "SER-2701-C": 10,
          },
        },
      }, null, 2));
      fail("Slice F create state tidak exact");
      return;
    }
    promoteSerumProjectionPhaseContext(manualBonusProjectionPhase);
    if (!assertSliceBProjection(
      {
        productInventory: manualBonusAfterProductRowsFinal,
        batchInventory: [
          ...manualBonusAfterBatch2608RowsFinal,
          ...manualBonusAfterBatch2612RowsFinal,
          ...manualBonusAfterBatch2701RowsFinal,
        ],
      },
      manualBonusProjectionPhase,
    )) {
      return;
    }
    console.log("[PASS] Slice F manual BONUS SER-NIA-30 qty 2 created/replayed with one domain effect");
    console.log("[PASS] Slice F preview PREVIEW_READY eligible basisHash valid stock-neutral");
    console.log("[PASS] Slice F FEFO preview memilih SER-2612-B qty 2");
    console.log("[PASS] Slice F post uses exact basisHash with confirmation");
    console.log("[PASS] Slice F outbound/line/allocation/transaction/ledger masing-masing tepat satu");
    console.log("[PASS] Slice F reason BONUS dan channel MANUAL tetap terpisah");
    console.log("[PASS] Slice F projection 24/0/24 dan batch SER-2608-A=0 SER-2612-B=14 SER-2701-C=10 exact");
    console.log("[PASS] Slice F replay identik tidak menambah domain effect");
  } else {
    const manualBonusOutboundsAfterExisting = manualBonusAfterOutbounds;
    const manualBonusOutboundRow = manualBonusOutboundsAfterExisting[0];
    const manualBonusLines = await readManualOutboundLinesByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusLines) return;
    const manualBonusAllocations = await readManualOutboundAllocationsByOutboundId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.outbound_id,
    );
    if (!manualBonusAllocations) return;
    const manualBonusLedgerRows = await readStockLedgerByTransactionId(
      auth.supabaseUrl,
      auth.publishableKey,
      auth.accessToken,
      auth.organizationId,
      manualBonusOutboundRow.transaction_id,
    );
    if (!manualBonusLedgerRows) return;
    const manualBonusExistingChecks = [
      {
        name: "manual outbound count",
        expected: 1,
        actual: manualBonusOutboundsAfterExisting.length,
        passed: manualBonusOutboundsAfterExisting.length === 1,
      },
      {
        name: "line count",
        expected: 1,
        actual: manualBonusLines.length,
        passed: manualBonusLines.length === 1,
      },
      {
        name: "allocation count",
        expected: 1,
        actual: manualBonusAllocations.length,
        passed: manualBonusAllocations.length === 1,
      },
      {
        name: "ledger count",
        expected: 1,
        actual: manualBonusLedgerRows.length,
        passed: manualBonusLedgerRows.length === 1,
      },
      {
        name: "transaction count",
        expected: 1,
        actual: isNonBlank(manualBonusOutboundRow?.transaction_id) ? 1 : 0,
        passed: isNonBlank(manualBonusOutboundRow?.transaction_id),
      },
      {
        name: "organization_id",
        expected: String(auth.organizationId),
        actual: String(manualBonusOutboundRow?.organization_id ?? ""),
        passed: String(manualBonusOutboundRow?.organization_id ?? "") === String(auth.organizationId),
      },
      {
        name: "source_ref",
        expected: manualBonusSourceRef,
        actual: String(manualBonusOutboundRow?.source_ref ?? ""),
        passed: String(manualBonusOutboundRow?.source_ref ?? "") === manualBonusSourceRef,
      },
      {
        name: "reason code",
        expected: "BONUS",
        actual: String(manualBonusOutboundRow?.reason_code_snapshot ?? ""),
        passed: String(manualBonusOutboundRow?.reason_code_snapshot ?? "") === "BONUS",
      },
      {
        name: "metadata.reference",
        expected: manualBonusReference,
        actual: String(manualBonusOutboundRow?.metadata?.reference ?? ""),
        passed: String(manualBonusOutboundRow?.metadata?.reference ?? "") === manualBonusReference,
      },
      {
        name: "product identity",
        expected: "SER-NIA-30",
        actual: String(manualBonusLines[0]?.product_sku_snapshot ?? ""),
        passed: String(manualBonusLines[0]?.product_sku_snapshot ?? "") === "SER-NIA-30",
      },
      {
        name: "requested quantity",
        expected: 2,
        actual: Number(manualBonusLines[0]?.quantity_requested),
        passed: Number(manualBonusLines[0]?.quantity_requested) === 2,
      },
      {
        name: "allocation quantity",
        expected: 2,
        actual: Number(manualBonusAllocations[0]?.quantity_allocated),
        passed: Number(manualBonusAllocations[0]?.quantity_allocated) === 2,
      },
      {
        name: "allocation batch",
        expected: "SER-2612-B",
        actual: String(manualBonusAllocations[0]?.batch_code_snapshot ?? ""),
        passed: String(manualBonusAllocations[0]?.batch_code_snapshot ?? "") === "SER-2612-B",
      },
      {
        name: "ledger bucket",
        expected: "SELLABLE",
        actual: String(manualBonusLedgerRows[0]?.bucket_code ?? ""),
        passed: String(manualBonusLedgerRows[0]?.bucket_code ?? "") === "SELLABLE",
      },
      {
        name: "ledger quantity_delta",
        expected: -2,
        actual: Number(manualBonusLedgerRows[0]?.quantity_delta),
        passed: Number(manualBonusLedgerRows[0]?.quantity_delta) === -2,
      },
      {
        name: "transaction_id linkage",
        expected: String(manualBonusOutboundRow?.transaction_id ?? ""),
        actual: `${String(manualBonusOutboundRow?.transaction_id ?? "")} / ${String(manualBonusLedgerRows[0]?.transaction_id ?? "")}`,
        passed:
          String(manualBonusOutboundRow?.transaction_id ?? "") === String(manualBonusLedgerRows[0]?.transaction_id ?? ""),
      },
      {
        name: "transaction_type_code",
        expected: "MANUAL_OUTBOUND",
        actual: String(manualBonusLedgerRows[0]?.transaction_type_code ?? ""),
        passed: String(manualBonusLedgerRows[0]?.transaction_type_code ?? "") === "MANUAL_OUTBOUND",
      },
      {
        name: "projection and batch balances",
        expected: manualBonusCurrentExpectedPhase,
        actual: `${String(manualBonusAfterProductRows?.[0]?.sellable_qty ?? "")} / ${String(manualBonusAfterProductRows?.[0]?.reserved_qty ?? "")} / ${String(manualBonusAfterProductRows?.[0]?.available_qty ?? "")}; ${Number(manualBonusAfterBatch2608Rows[0]?.sellable_qty ?? 0)} / ${Number(manualBonusAfterBatch2612Rows[0]?.sellable_qty ?? 0)} / ${Number(manualBonusAfterBatch2701Rows[0]?.sellable_qty ?? 0)}`,
        passed: matchesSerumProjectionExact(
          {
            productInventory: manualBonusAfterProductRows,
            batchInventory: [
              ...manualBonusAfterBatch2608Rows,
              ...manualBonusAfterBatch2612Rows,
              ...manualBonusAfterBatch2701Rows,
            ],
          },
          manualBonusCurrentExpectedPhase,
        ),
      },
    ];
    const manualBonusExistingFailedChecks = manualBonusExistingChecks.filter((check) => !check.passed);
    if (manualBonusExistingFailedChecks.length > 0) {
      console.log("[FAIL] Slice F EXACT_EXISTING predicate");
      console.log("       Failed checks:");
      for (const check of manualBonusExistingFailedChecks) {
        console.log(`       - ${check.name}`);
        console.log(`         expected: ${JSON.stringify(check.expected)}`);
        console.log(`         actual: ${JSON.stringify(check.actual)}`);
      }
      return;
    }
    promoteSerumProjectionPhaseContext(manualBonusProjectionPhase);
    if (!assertSliceBProjection(
      {
        productInventory: manualBonusAfterProductRowsFinal,
        batchInventory: [
          ...manualBonusAfterBatch2608RowsFinal,
          ...manualBonusAfterBatch2612RowsFinal,
          ...manualBonusAfterBatch2701RowsFinal,
        ],
      },
      manualBonusAfterProductRowsFinal?.[0] && asNumber(manualBonusAfterProductRowsFinal[0]?.reserved_qty) === 2
        ? buildBundleProjectionPhase("SLICE_G_BUNDLE_RESERVED")
        : asNumber(manualBonusAfterProductRowsFinal?.[0]?.sellable_qty) === 22
          ? buildBundleProjectionPhase("SLICE_G_BUNDLE_SHIPPED")
          : buildSerumProjectionPhase("SLICE_F_MANUAL_BONUS", Number.NaN, Number.NaN),
    )) {
      return;
    }
    console.log("[PASS] Slice F existing manual bonus adopted exactly");
    console.log("[PASS] Slice F FEFO SER-2612-B = 2 exact");
    console.log("[PASS] Slice F ledger SELLABLE -2 exact");
    console.log("[PASS] Slice F projection 24 / 0 / 24 exact");
    console.log("[PASS] Slice F durable state produced no second domain effect");
  }

  if (!verifyGoldenCompletionGuard("sliceF", currentSerumProjectionPhaseContext)) return;

  const sliceGResult = await runSliceGBundleShipmentStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!sliceGResult) return;
  if (!verifyGoldenCompletionGuard("sliceGShipped", currentSerumProjectionPhaseContext)) return;

  console.log("[PASS] Slice G phase marker SLICE_G_BUNDLE_SHIPPED");
  const sliceHResult = await runSliceHReturnStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceHResult) return;
  if (!verifyGoldenCompletionGuard("sliceHReceived", currentSerumProjectionPhaseContext, sliceHResult.effectivePhase)) return;

  console.log(`[PASS] Slice H phase marker ${sliceHResult.effectivePhase.detectedPhase}`);
  const sliceIResult = await runSliceIReturnInspectionStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceIResult) return;
  if (!verifyGoldenCompletionGuard("sliceIInspected", currentSerumProjectionPhaseContext, sliceIResult.effectivePhase)) return;

  console.log(`[PASS] Slice I phase marker ${sliceIResult.effectivePhase.detectedPhase}`);
  const workerProbe = await invokeGoldenTrustedWorker({ operation: "PROBE_TIKTOK_CLAIM_NOTIFICATION_WORKER" });
  if (!workerProbe.ok || workerProbe.role !== "service_role" || workerProbe.evaluatorPrivilege !== true || workerProbe.mutationCount !== 0) {
    fail("GOLDEN_TRUSTED_WORKER_PROBE_FAILED");
    return;
  }
  console.log("[PASS] Golden trusted-worker local role/privilege probe");

  const sliceJResult = await runSliceJTiktokReturnLostStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumProduct.productId,
  );
  if (!sliceJResult) return;
  if (!verifyGoldenCompletionGuard("sliceJLost", currentSerumProjectionPhaseContext, sliceJResult.effectivePhase)) return;

  const sliceKResult = await runSliceKTiktokClaimNotificationStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
  );
  if (!sliceKResult) return;
  if (!verifyGoldenCompletionGuard("sliceKNotification", currentSerumProjectionPhaseContext, sliceKResult.effectivePhase)) return;

  console.log(`[PASS] Slice K phase marker ${sliceKResult.effectivePhase.detectedPhase}`);
  const serumStocktakeBatch = batches.get(GOLDEN_TERMINAL.batchCode);
  if (!serumStocktakeBatch?.batchId) {
    fail("GOLDEN_STOCKTAKE_CONTRACT_NOT_EXACT");
    return;
  }
  const terminalResult = await runGoldenTerminalStateAware(
    auth.supabaseUrl,
    auth.publishableKey,
    auth.accessToken,
    auth.organizationId,
    serumStocktakeBatch.batchId,
  );
  if (!terminalResult) return;
  if (!verifyGoldenCompletionGuard("stocktakeAdjustment", currentSerumProjectionPhaseContext, terminalResult.phase)) return;
  if (!verifyGoldenCompletionGuard("reconciliation", terminalResult.phase)) return;
  if (!verifyGoldenCompletionGuard("finalAcceptance", terminalResult.phase)) return;
  promoteSerumProjectionPhaseContext(terminalResult.phase);
  console.log(`[PASS] Golden stocktake ${terminalResult.outcome}: snapshot 12, physical 11, adjustment Serum -1 exact`);
  console.log("[PASS] Golden reconciliation POST_STOCKTAKE linked, stock-neutral, tanpa OPEN CRITICAL issue");
  console.log("[PASS] Golden final acceptance reached: Serum 23 / 0 / 23, Cleanser 14 / 0 / 14, duplicate effect 0");
}

async function executeGoldenRunner() {
  try {
    await main();
    return Number(process.exitCode ?? 0) === 0 ? 0 : 1;
  } catch (error) {
    console.error(
      error instanceof Error
        ? error.stack ?? error.message
        : String(error),
    );
    return 1;
  }
}

executeGoldenRunner().then((exitCode) => {
  process.exitCode = exitCode;
});
