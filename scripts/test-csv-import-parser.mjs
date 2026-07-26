import assert from "node:assert/strict";
import { parseMarketplaceCsv } from "../src/lib/csv-import/parser.ts";

const valid = await parseMarketplaceCsv(
  new TextEncoder().encode(
    "\uFEFFschema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,event_type,source_title\r\n" +
      "MARKETPLACE_RESERVATION_V1,CSV061,EVT-1,ORD-1,READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,L1,SINGLE-061,2,ORDER,\"Serum, A\"\r\n" +
      "MARKETPLACE_RESERVATION_V1,CSV061,EVT-1,ORD-1,READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,L2,SINGLE-061,1,RESERVE,\"Quoted \"\"title\"\"\"\r\n",
  ),
  "orders.csv",
  "text/csv",
);
assert.equal(valid.errors.length, 0);
assert.equal(valid.rows.length, 2);
assert.equal(valid.events.length, 1);
assert.equal(valid.events[0].rows.length, 2);
assert.equal(valid.rows[0].normalizedRow.source_title, "Serum, A");
assert.equal(valid.rows[1].normalizedRow.source_title, 'Quoted "title"');

const formula = await parseMarketplaceCsv(
  new TextEncoder().encode(
    "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity\n" +
      "MARKETPLACE_RESERVATION_V1,CSV061,EVT-F,ORD-F,READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,L-F,SINGLE-061,=2\n",
  ),
  "formula.csv",
  "text/csv",
);
assert.ok(formula.rows[0].errors.some(({ code }) => code === "INVALID_QUANTITY"));
assert.equal(formula.rows[0].rawRow.listing_quantity, "=2");

const malformed = await parseMarketplaceCsv(
  new TextEncoder().encode(
    "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,unknown\n" +
      "MARKETPLACE_RESERVATION_V1,CSV061,EVT-B,ORD-B,READY_TO_SHIP,not-a-date,2026-07-26T09:01:00Z,L1,SINGLE-061,1,unexpected\n",
  ),
  "malformed.csv",
  "text/csv",
);
assert.ok(malformed.errors.some(({ code }) => code === "UNKNOWN_HEADER"));

const invalidTimestamp = await parseMarketplaceCsv(
  new TextEncoder().encode(
    "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity\n" +
      "MARKETPLACE_RESERVATION_V1,CSV061,EVT-T,ORD-T,READY_TO_SHIP,not-a-date,2026-07-26T09:01:00Z,L1,SINGLE-061,1\n",
  ),
  "invalid-timestamp.csv",
  "text/csv",
);
assert.ok(invalidTimestamp.rows[0].errors.some(({ code }) => code === "INVALID_TIMESTAMP"));

console.log("CSV parser focused checks: PASS");
