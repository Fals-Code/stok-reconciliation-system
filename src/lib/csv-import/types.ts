export const CSV_IMPORT_TEMPLATE_VERSION = "MARKETPLACE_RESERVATION_V1" as const;
export const CSV_IMPORT_KIND = "ORDER" as const;
export const CSV_IMPORT_MAX_FILE_BYTES = 10 * 1024 * 1024;
export const CSV_IMPORT_MAX_ROWS = 100_000;
export const CSV_IMPORT_MAX_EVENT_LINES = 100;
export const CSV_IMPORT_MAX_EXPANDED_LINES = 200;
export const CSV_IMPORT_MAX_FIELD_LENGTH = 2_000;

export const CSV_IMPORT_REQUIRED_HEADERS = [
  "schema_version",
  "channel_code",
  "external_event_ref",
  "external_order_ref",
  "source_status",
  "occurred_at",
  "received_at",
  "source_line_ref",
  "external_listing_code",
  "listing_quantity",
] as const;

export const CSV_IMPORT_OPTIONAL_HEADERS = [
  "event_type",
  "source_title",
  "source_sku",
  "note",
] as const;

export type CsvImportHeader =
  | (typeof CSV_IMPORT_REQUIRED_HEADERS)[number]
  | (typeof CSV_IMPORT_OPTIONAL_HEADERS)[number];

export type CsvImportErrorSeverity = "BLOCKING" | "WARNING";

export type CsvImportValidationError = {
  field: string | null;
  code: string;
  message: string;
  remediation: string;
  severity: CsvImportErrorSeverity;
};

export type CsvImportRow = {
  rowNumber: number;
  rawRow: Record<string, string>;
  normalizedRow: Record<string, string | number | null>;
  rowFingerprint: string;
  eventGroupKey: string | null;
  externalEventRef: string | null;
  canonicalIdempotencyKey: string | null;
  errors: CsvImportValidationError[];
  expansionPreview: Record<string, unknown> | null;
};

export type CsvImportEvent = {
  eventGroupKey: string;
  channelCode: string;
  externalEventRef: string;
  externalOrderRef: string;
  sourceStatus: string;
  occurredAt: string;
  receivedAt: string;
  note: string | null;
  rows: CsvImportRow[];
};

export type CsvImportParseResult = {
  text: string;
  fileSha256: string;
  detectedMime: "text/csv";
  headers: string[];
  rows: CsvImportRow[];
  events: CsvImportEvent[];
  errors: CsvImportValidationError[];
};

export type CsvImportJobReadModel = {
  id: string;
  organization_id: string;
  import_type_code: string;
  template_version: string;
  status_code: string;
  original_file_name: string;
  detected_mime: string;
  file_size_bytes: number;
  row_count: number;
  valid_row_count: number;
  invalid_row_count: number;
  duplicate_row_count: number;
  conflict_row_count: number;
  processed_row_count: number;
  expanded_line_count: number;
  failure_code: string | null;
  failure_detail: string | null;
  uploaded_at: string;
  validated_at: string | null;
  committed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type CsvImportRowReadModel = {
  id: string;
  organization_id: string;
  import_job_id: string;
  row_number: number;
  normalized_row: Record<string, unknown>;
  row_fingerprint: string;
  validation_status_code: string;
  validation_errors: CsvImportValidationError[];
  processing_status_code: string;
  external_event_ref: string | null;
  canonical_idempotency_key: string | null;
  result_entity_type: string | null;
  result_entity_id: string | null;
  canonical_line_count: number;
  event_group_key: string | null;
  expansion_preview: Record<string, unknown> | null;
  processed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type CsvImportPage<T> = {
  rows: T[];
  nextCursor: string | number | null;
  hasMore: boolean;
};
