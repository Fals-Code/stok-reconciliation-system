import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  safeMarketplaceCsvCommitErrorCode,
  safeMarketplaceCsvUploadErrorCode,
} from "../src/lib/csv-import/safe-errors.ts";

const sensitiveMarker = "integration.import_jobs SQL_HINT storage/imports/internal.csv";
const backendError = new Error(
  `PGRST204 | ${sensitiveMarker} | hint: internal function detail | code: XX999`,
);

assert.equal(
  safeMarketplaceCsvUploadErrorCode(backendError),
  "CSV_IMPORT_UPLOAD_FAILED",
  "unknown backend upload errors map to a stable safe code",
);
assert.equal(
  safeMarketplaceCsvCommitErrorCode(backendError),
  "CSV_IMPORT_COMMIT_FAILED",
  "unknown backend commit errors map to a stable safe code",
);
assert.equal(
  safeMarketplaceCsvUploadErrorCode("INVALID_EXTENSION"),
  "INVALID_EXTENSION",
  "known validation errors remain actionable",
);

const actionSource = await readFile("src/app/marketplace/import/actions.ts", "utf8");
assert.match(actionSource, /errorCode=/, "upload redirect uses an error code parameter");
assert.doesNotMatch(actionSource, /error\.message/, "Server Action does not redirect raw exception messages");

const pageSource = await readFile("src/app/marketplace/import/page.tsx", "utf8");
assert.match(pageSource, /File belum dapat diproses/, "upload page has a safe actionable fallback message");
assert.doesNotMatch(pageSource, /query\.error\b/, "upload page does not render the old raw error parameter");

const detailSource = await readFile("src/app/marketplace/import/[jobId]/page.tsx", "utf8");
assert.match(detailSource, /safeMarketplaceCsvCommitErrorCode/, "commit detail sanitizes the query code");
assert.doesNotMatch(detailSource, /query\.commitError\}/, "commit detail does not render raw backend error text");

console.log("CSV import error boundary focused checks: PASS");
