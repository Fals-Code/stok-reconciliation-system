import { createHash } from "node:crypto";
import { parse } from "csv-parse/sync";

import {
  CSV_IMPORT_MAX_EVENT_LINES,
  CSV_IMPORT_MAX_FIELD_LENGTH,
  CSV_IMPORT_MAX_ROWS,
  CSV_IMPORT_MAX_EXPANDED_LINES,
  CSV_IMPORT_OPTIONAL_HEADERS,
  CSV_IMPORT_REQUIRED_HEADERS,
  CSV_IMPORT_TEMPLATE_VERSION,
  type CsvImportErrorSeverity,
  type CsvImportEvent,
  type CsvImportParseResult,
  type CsvImportRow,
  type CsvImportValidationError,
} from "./types.ts";

const ALLOWED_EVENT_TYPES = new Set(["ORDER", "RESERVE"]);

function error(
  field: string | null,
  code: string,
  message: string,
  remediation: string,
  severity: CsvImportErrorSeverity = "BLOCKING",
): CsvImportValidationError {
  return { field, code, message, remediation, severity };
}

function normalize(value: string) {
  return value.replace(/^\uFEFF/, "").trim();
}

function sha256(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function rowFingerprint(row: Record<string, string>) {
  const canonical = JSON.stringify(
    Object.keys(row)
      .sort()
      .map((key) => [key, row[key]]),
  );
  return sha256(Buffer.from(canonical, "utf8"));
}

function eventGroupKey(row: Record<string, string>) {
  const eventRef = normalize(row.external_event_ref ?? "");
  return eventRef ? `${normalize(row.channel_code ?? "").toUpperCase()}|${eventRef}` : null;
}

function parsedDate(value: string) {
  const normalized = normalize(value);
  if (!normalized || Number.isNaN(Date.parse(normalized))) return null;
  return new Date(normalized).toISOString();
}

function parseQuantity(value: string) {
  const normalized = normalize(value);
  if (!/^[1-9][0-9]{0,8}$/.test(normalized)) return null;
  const quantity = Number(normalized);
  return Number.isSafeInteger(quantity) && quantity > 0 ? quantity : null;
}

function validateHeaders(headers: string[]) {
  const normalized = headers.map(normalize);
  const errors: CsvImportValidationError[] = [];
  const duplicates = normalized.filter(
    (header, index) => normalized.indexOf(header) !== index,
  );

  if (duplicates.length > 0) {
    errors.push(
      error(
        null,
        "DUPLICATE_HEADER",
        "Header CSV tidak boleh duplikat.",
        "Hapus header yang berulang dan gunakan template v1.",
      ),
    );
  }

  for (const header of CSV_IMPORT_REQUIRED_HEADERS) {
    if (!normalized.includes(header)) {
      errors.push(
        error(
          header,
          "MISSING_HEADER",
          `Header wajib ${header} tidak ditemukan.`,
          "Tambahkan header wajib sesuai template v1.",
        ),
      );
    }
  }

  const supported = new Set([
    ...CSV_IMPORT_REQUIRED_HEADERS,
    ...CSV_IMPORT_OPTIONAL_HEADERS,
  ]);
  for (const header of normalized) {
    if (header && !supported.has(header as never)) {
      errors.push(
        error(
          header,
          "UNKNOWN_HEADER",
          `Header ${header} tidak didukung oleh template v1.`,
          "Hapus kolom tersebut atau gunakan schema yang didukung.",
        ),
      );
    }
  }

  return { normalized, errors };
}

function rowErrors(
  row: Record<string, string>,
  rowNumber: number,
): { errors: CsvImportValidationError[]; normalized: Record<string, string | number | null> } {
  const errors: CsvImportValidationError[] = [];
  const normalized: Record<string, string | number | null> = {};
  const textFields = [
    "channel_code",
    "external_event_ref",
    "external_order_ref",
    "source_status",
    "source_line_ref",
    "external_listing_code",
    "source_title",
    "source_sku",
    "note",
  ];

  for (const field of textFields) {
    const value = normalize(row[field] ?? "");
    normalized[field] = value || null;
    if (value.length > CSV_IMPORT_MAX_FIELD_LENGTH) {
      errors.push(
        error(field, "FIELD_TOO_LONG", `Nilai ${field} terlalu panjang.`, "Pendekkan nilai sesuai batas field.")
      );
    }
  }

  const schemaVersion = normalize(row.schema_version ?? "");
  normalized.schema_version = schemaVersion || null;
  if (schemaVersion !== CSV_IMPORT_TEMPLATE_VERSION) {
    errors.push(
      error("schema_version", "UNSUPPORTED_SCHEMA_VERSION", "Schema CSV tidak didukung.", "Gunakan MARKETPLACE_RESERVATION_V1.")
    );
  }

  const eventType = normalize(row.event_type ?? "").toUpperCase();
  normalized.event_type = eventType || null;
  if (eventType && !ALLOWED_EVENT_TYPES.has(eventType)) {
    errors.push(
      error("event_type", "UNSUPPORTED_EVENT_TYPE", "Event type CSV tidak didukung.", "Gunakan ORDER atau RESERVE; domain event tetap ditentukan server.")
    );
  }

  for (const field of ["channel_code", "external_event_ref", "external_order_ref", "source_status", "source_line_ref", "external_listing_code"]) {
    if (!normalized[field]) {
      errors.push(error(field, "REQUIRED_FIELD", `Field ${field} wajib diisi.`, "Isi field sesuai kontrak event canonical."));
    }
  }

  const sourceStatus = String(normalized.source_status ?? "").toUpperCase();
  normalized.source_status = sourceStatus || null;
  if (sourceStatus && !/^[A-Z][A-Z0-9_ -]{0,99}$/.test(sourceStatus)) {
    errors.push(error("source_status", "INVALID_SOURCE_STATUS", "Source status tidak valid.", "Gunakan nilai status yang diterima marketplace boundary."));
  }

  const occurredAt = parsedDate(row.occurred_at ?? "");
  const receivedAt = parsedDate(row.received_at ?? "");
  normalized.occurred_at = occurredAt;
  normalized.received_at = receivedAt;
  if (!occurredAt) errors.push(error("occurred_at", "INVALID_TIMESTAMP", "occurred_at bukan timestamp valid.", "Gunakan timestamp ISO-8601."));
  if (!receivedAt) errors.push(error("received_at", "INVALID_TIMESTAMP", "received_at bukan timestamp valid.", "Gunakan timestamp ISO-8601."));
  if (occurredAt && receivedAt && Date.parse(receivedAt) < Date.parse(occurredAt)) {
    errors.push(error("received_at", "RECEIVED_BEFORE_OCCURRED", "received_at lebih awal dari occurred_at.", "Perbaiki urutan timestamp event."));
  }

  const quantity = parseQuantity(row.listing_quantity ?? "");
  normalized.listing_quantity = quantity;
  if (quantity === null) {
    errors.push(error("listing_quantity", "INVALID_QUANTITY", "listing_quantity harus integer positif.", "Gunakan bilangan bulat positif maksimal 9 digit."));
  }

  if (rowNumber > CSV_IMPORT_MAX_ROWS) {
    errors.push(error(null, "ROW_LIMIT_EXCEEDED", "Batas jumlah row terlampaui.", "Pecah file menjadi beberapa import."));
  }

  return { errors, normalized };
}

function groupEvents(rows: CsvImportRow[]): CsvImportEvent[] {
  const grouped = new Map<string, CsvImportRow[]>();
  for (const row of rows) {
    if (!row.eventGroupKey) continue;
    const current = grouped.get(row.eventGroupKey) ?? [];
    current.push(row);
    grouped.set(row.eventGroupKey, current);
  }

  return [...grouped.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, eventRows]) => {
      const first = eventRows[0];
      const values = first.normalizedRow;
      return {
        eventGroupKey: key,
        channelCode: String(values.channel_code ?? "").toUpperCase(),
        externalEventRef: String(values.external_event_ref ?? ""),
        externalOrderRef: String(values.external_order_ref ?? ""),
        sourceStatus: String(values.source_status ?? "").toUpperCase(),
        occurredAt: String(values.occurred_at ?? ""),
        receivedAt: String(values.received_at ?? ""),
        note: values.note ? String(values.note) : null,
        rows: eventRows.sort((a, b) => a.rowNumber - b.rowNumber),
      };
    });
}

export async function parseMarketplaceCsv(bytes: Uint8Array, fileName: string, clientMime: string | null): Promise<CsvImportParseResult> {
  const fileSha256 = sha256(bytes);
  const errors: CsvImportValidationError[] = [];
  const lowerName = fileName.trim().toLowerCase();
  if (!lowerName.endsWith(".csv")) errors.push(error(null, "INVALID_EXTENSION", "File harus berekstensi .csv.", "Pilih file CSV."));
  if (bytes.byteLength > 10 * 1024 * 1024) errors.push(error(null, "FILE_TOO_LARGE", "Ukuran file melebihi batas 10 MB.", "Pecah file sebelum upload."));
  if (clientMime && !["text/csv", "application/csv", "text/plain", "application/octet-stream"].includes(clientMime)) {
    errors.push(error(null, "INVALID_MIME", "Content-Type file tidak didukung.", "Gunakan file CSV teks."));
  }
  if (bytes.includes(0)) errors.push(error(null, "BINARY_CONTENT", "File mengandung byte binary/NUL.", "Simpan ulang sebagai UTF-8 CSV."));

  let text = "";
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    errors.push(error(null, "INVALID_UTF8", "File bukan UTF-8 yang valid.", "Simpan ulang file sebagai UTF-8."));
  }
  text = text.replace(/^\uFEFF/, "");
  if (errors.some((item) => item.code === "INVALID_UTF8" || item.code === "BINARY_CONTENT")) {
    return { text, fileSha256, detectedMime: "text/csv", headers: [], rows: [], events: [], errors };
  }

  let records: string[][] = [];
  try {
    records = parse(text, {
      bom: true,
      columns: false,
      skip_empty_lines: true,
      relax_column_count: true,
      max_record_size: CSV_IMPORT_MAX_FIELD_LENGTH * 50,
      trim: false,
    }) as string[][];
  } catch {
    errors.push(error(null, "MALFORMED_CSV", "Struktur CSV tidak dapat dibaca.", "Periksa quoted comma, escaped quote, dan newline dalam quote."));
    return { text, fileSha256, detectedMime: "text/csv", headers: [], rows: [], events: [], errors };
  }

  const headerRecord = records.shift() ?? [];
  const headerResult = validateHeaders(headerRecord);
  errors.push(...headerResult.errors);
  if (headerResult.errors.length > 0 || headerRecord.length === 0) {
    return { text, fileSha256, detectedMime: "text/csv", headers: headerResult.normalized, rows: [], events: [], errors };
  }

  const rows: CsvImportRow[] = [];
  for (const [index, values] of records.entries()) {
    const rowNumber = index + 2;
    const rawRow = Object.fromEntries(headerResult.normalized.map((header, column) => [header, values[column] ?? ""]));
    const rowValidation = rowErrors(rawRow, rowNumber);
    if (values.length !== headerResult.normalized.length) {
      rowValidation.errors.push(error(null, "UNEQUAL_COLUMNS", "Jumlah kolom row berbeda dari header.", "Lengkapi atau hapus kolom row tersebut."));
    }
    const groupKey = eventGroupKey(rawRow);
    const normalizedRow = rowValidation.normalized;
    const fingerprint = rowFingerprint(rawRow);
    rows.push({
      rowNumber,
      rawRow,
      normalizedRow,
      rowFingerprint: fingerprint,
      eventGroupKey: groupKey,
      externalEventRef: normalizedRow.external_event_ref ? String(normalizedRow.external_event_ref) : null,
      canonicalIdempotencyKey: groupKey ? `csv:${fileSha256}:${groupKey}` : null,
      errors: rowValidation.errors,
      expansionPreview: null,
    });
  }

  if (rows.length > CSV_IMPORT_MAX_ROWS) errors.push(error(null, "ROW_LIMIT_EXCEEDED", "Batas jumlah row terlampaui.", "Pecah file menjadi beberapa import."));
  for (const event of groupEvents(rows)) {
    if (event.rows.length > CSV_IMPORT_MAX_EVENT_LINES) {
      for (const row of event.rows) row.errors.push(error(null, "EVENT_LINE_LIMIT_EXCEEDED", "Jumlah source line dalam satu event melebihi batas.", "Pecah event berdasarkan external_event_ref."));
    }
    if (event.rows.some((row) => row.errors.length === 0)) {
      for (const row of event.rows) {
        if (row.normalizedRow.listing_quantity && Number(row.normalizedRow.listing_quantity) > CSV_IMPORT_MAX_EXPANDED_LINES * 1_000_000) {
          row.errors.push(error("listing_quantity", "EXPANDED_LINE_LIMIT_EXCEEDED", "Perkiraan expansion melebihi batas aman.", "Kurangi quantity atau pecah event."));
        }
      }
    }
  }

  const events = groupEvents(rows);
  for (const event of events) {
    const eventValues = event.rows.map((row) => row.normalizedRow);
    for (const field of ["channel_code", "external_order_ref", "source_status", "occurred_at", "received_at"]) {
      const distinct = new Set(eventValues.map((value) => String(value[field] ?? "")));
      if (distinct.size > 1) {
        for (const row of event.rows) row.errors.push(error(field, "EVENT_IDENTITY_CONFLICT", `Nilai ${field} berbeda dalam satu external_event_ref.`, "Gunakan satu nilai event-level yang konsisten."));
      }
    }
    const lineRefs = new Set<string>();
    for (const row of event.rows) {
      const ref = String(row.normalizedRow.source_line_ref ?? "");
      if (ref && lineRefs.has(ref)) row.errors.push(error("source_line_ref", "DUPLICATE_SOURCE_LINE", "source_line_ref duplikat dalam event.", "Gunakan source line reference unik."));
      lineRefs.add(ref);
    }
  }

  return { text, fileSha256, detectedMime: "text/csv", headers: headerResult.normalized, rows, events, errors };
}
