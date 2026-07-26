import "server-only";

import { createHash } from "node:crypto";

import { getAdminSession } from "@/lib/auth";

import { parseMarketplaceCsv } from "./parser";
import {
  CSV_IMPORT_TEMPLATE_VERSION,
  type CsvImportJobReadModel,
  type CsvImportCommitReadModel,
  type CsvImportCommitResult,
  type CsvImportEventResultReadModel,
  type CsvImportPage,
  type CsvImportParseResult,
  type CsvImportRowReadModel,
} from "./types";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";

type RpcEnvelope = Record<string, unknown>;

function config() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(/\/$/, "");
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const secretKey = process.env.SUPABASE_SECRET_KEY;
  if (!publishableKey || !secretKey) throw new Error("SUPABASE_SERVER_CONFIGURATION_REQUIRED");
  return { url, publishableKey, secretKey };
}

async function responseError(response: Response) {
  const raw = await response.text();
  if (!raw) return `${response.status} ${response.statusText}`;
  try {
    const parsed = JSON.parse(raw) as { message?: string; details?: string; hint?: string; code?: string };
    return [parsed.message, parsed.details, parsed.hint, parsed.code].filter(Boolean).join(" | ") || raw;
  } catch {
    return raw;
  }
}

async function rpc<T>(name: string, body: RpcEnvelope, token: string, key: string) {
  const { url } = config();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "Accept-Profile": "api",
      "Content-Profile": "api",
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(await responseError(response));
  return (await response.json()) as T;
}

async function readApi<T>(path: string, session: { accessToken: string }) {
  const { url, publishableKey } = config();
  const response = await fetch(`${url}/rest/v1/${path}`, {
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${session.accessToken}`,
      Accept: "application/json",
      "Accept-Profile": "api",
    },
    cache: "no-store",
  });
  if (!response.ok) throw new Error(await responseError(response));
  return (await response.json()) as T;
}

function objectPathSegments(path: string) {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}

async function storageUpload(path: string, bytes: Uint8Array, mime: string, token: string) {
  const { url, secretKey } = config();
  const response = await fetch(`${url}/storage/v1/object/imports/${objectPathSegments(path)}`, {
    method: "POST",
    headers: {
      apikey: secretKey,
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": mime,
      "x-upsert": "false",
      "cache-control": "no-store",
    },
    body: Buffer.from(bytes),
  });
  if (!response.ok) throw new Error(await responseError(response));
  void token;
}

async function storageDelete(path: string) {
  const { url, secretKey } = config();
  await fetch(`${url}/storage/v1/object/imports/${objectPathSegments(path)}`, {
    method: "DELETE",
    headers: { apikey: secretKey, Authorization: `Bearer ${secretKey}` },
    cache: "no-store",
  }).catch(() => undefined);
}

function requestHash(result: CsvImportParseResult, fileName: string) {
  const payload = JSON.stringify({
    templateVersion: CSV_IMPORT_TEMPLATE_VERSION,
    fileName,
    fileSha256: result.fileSha256,
    detectedMime: result.detectedMime,
    rows: result.rows.map((row) => ({
      rowNumber: row.rowNumber,
      rowFingerprint: row.rowFingerprint,
      normalizedRow: row.normalizedRow,
      eventGroupKey: row.eventGroupKey,
      errors: row.errors,
    })),
  });
  return createHash("sha256").update(payload, "utf8").digest("hex");
}

function safeCommitError(error: unknown) {
  const message = error instanceof Error ? error.message : "";
  const code = message.split("|")[0]?.trim() ?? "";
  if (/^(CSV_|MARKETPLACE_|IDEMPOTENCY_)[A-Z0-9_]*$/.test(code)) return new Error(code);
  return new Error("CSV_IMPORT_COMMIT_FAILED");
}

export type CsvImportUploadResult = {
  status: string;
  jobId: string | null;
  parse: CsvImportParseResult;
  summary: Record<string, unknown> | null;
};

export async function uploadAndValidateMarketplaceCsv(file: File): Promise<CsvImportUploadResult> {
  const session = await getAdminSession();
  if (!session) throw new Error("AUTH_SESSION_REQUIRED");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const parsed = await parseMarketplaceCsv(bytes, file.name, file.type || null);
  const hardFileErrors = new Set(["INVALID_EXTENSION", "FILE_TOO_LARGE", "INVALID_MIME", "BINARY_CONTENT", "INVALID_UTF8"]);
  if (parsed.errors.some((item) => hardFileErrors.has(item.code))) {
    return { status: "VALIDATION_FAILED", jobId: null, parse: parsed, summary: null };
  }

  const { publishableKey, secretKey } = config();
  const jobCommandKey = `csv-import:${CSV_IMPORT_TEMPLATE_VERSION}:${parsed.fileSha256}`;
  const created = await rpc<{ status: string; jobId?: string; objectPath?: string }>(
    "create_marketplace_csv_import_job",
    {
      p_job_command_key: jobCommandKey,
      p_request_hash: requestHash(parsed, file.name),
      p_original_file_name: file.name,
      p_detected_mime: parsed.detectedMime,
      p_file_size_bytes: bytes.byteLength,
      p_file_sha256: parsed.fileSha256,
    },
    session.accessToken,
    publishableKey,
  );

  if (created.status !== "CREATED" || !created.jobId || !created.objectPath) {
    return { status: created.status, jobId: created.jobId ?? null, parse: parsed, summary: created };
  }

  let uploaded = false;
  try {
    await storageUpload(created.objectPath, bytes, parsed.detectedMime, session.accessToken);
    uploaded = true;
    const summary = await rpc<Record<string, unknown>>(
      "validate_marketplace_csv_import_job",
      {
        p_organization_id: session.profile.organization_id,
        p_job_id: created.jobId,
        p_file_sha256: parsed.fileSha256,
        p_rows: parsed.rows,
        p_parse_errors: parsed.errors,
      },
      secretKey,
      secretKey,
    );
    return { status: String(summary.status ?? "VALIDATION_FAILED"), jobId: created.jobId, parse: parsed, summary };
  } catch (error) {
    if (uploaded || created.objectPath) await storageDelete(created.objectPath);
    throw error;
  }
}

export async function getMarketplaceCsvImportJobs(limit = 50, cursor: string | null = null): Promise<CsvImportPage<CsvImportJobReadModel>> {
  const session = await getAdminSession();
  if (!session) throw new Error("AUTH_SESSION_REQUIRED");
  const organization = encodeURIComponent(session.profile.organization_id);
  const boundedLimit = Math.min(Math.max(limit, 1), 100);
  const filters = [`organization_id=eq.${organization}`];
  if (cursor) filters.push(`created_at=lt.${encodeURIComponent(cursor)}`);
  const rows = await readApi<CsvImportJobReadModel[]>(
    `import_job_read_model?${filters.join("&")}&select=*&order=created_at.desc,id.desc&limit=${boundedLimit + 1}`,
    session,
  );
  const pageRows = rows.slice(0, boundedLimit);
  return { rows: pageRows, nextCursor: rows.length > boundedLimit ? pageRows.at(-1)?.created_at ?? null : null, hasMore: rows.length > boundedLimit };
}

export async function getMarketplaceCsvImportJob(jobId: string): Promise<CsvImportJobReadModel | null> {
  const session = await getAdminSession();
  if (!session || !/^[0-9a-f-]{36}$/i.test(jobId)) return null;
  const organization = encodeURIComponent(session.profile.organization_id);
  const id = encodeURIComponent(jobId);
  const rows = await readApi<CsvImportJobReadModel[]>(`import_job_read_model?organization_id=eq.${organization}&id=eq.${id}&select=*&limit=1`, session);
  return rows[0] ?? null;
}

export async function getMarketplaceCsvImportRows(jobId: string, limit = 100, cursor: number | null = null, status: string | null = null): Promise<CsvImportPage<CsvImportRowReadModel>> {
  const session = await getAdminSession();
  if (!session || !/^[0-9a-f-]{36}$/i.test(jobId)) return { rows: [], nextCursor: null, hasMore: false };
  const organization = encodeURIComponent(session.profile.organization_id);
  const id = encodeURIComponent(jobId);
  const boundedLimit = Math.min(Math.max(limit, 1), 200);
  const filters = [`organization_id=eq.${organization}`, `import_job_id=eq.${id}`];
  if (cursor !== null && Number.isSafeInteger(cursor) && cursor > 0) filters.push(`row_number=gt.${cursor}`);
  if (status && /^[A-Z_]+$/.test(status)) filters.push(`validation_status_code=eq.${encodeURIComponent(status)}`);
  const rows = await readApi<CsvImportRowReadModel[]>(`import_row_preview_read_model?${filters.join("&")}&select=*&order=row_number.asc,id.asc&limit=${boundedLimit + 1}`, session);
  const pageRows = rows.slice(0, boundedLimit);
  return { rows: pageRows, nextCursor: rows.length > boundedLimit ? pageRows.at(-1)?.row_number ?? null : null, hasMore: rows.length > boundedLimit };
}

export async function commitMarketplaceCsvImportJob(
  jobId: string,
  commitIdempotencyKey: string,
  confirmation = false,
): Promise<CsvImportCommitResult> {
  const session = await getAdminSession();
  if (!session || !/^[0-9a-f-]{36}$/i.test(jobId)) throw new Error("CSV_IMPORT_JOB_NOT_FOUND");
  if (!confirmation) throw new Error("CSV_IMPORT_COMMIT_CONFIRMATION_REQUIRED");
  if (!/^[A-Za-z0-9:_-]{1,200}$/.test(commitIdempotencyKey)) throw new Error("CSV_IMPORT_COMMIT_KEY_INVALID");
  const { secretKey } = config();
  try {
    return await rpc<CsvImportCommitResult>(
      "commit_marketplace_csv_import_job",
      {
        p_organization_id: session.profile.organization_id,
        p_import_job_id: jobId,
        p_commit_idempotency_key: commitIdempotencyKey,
        p_confirmation: true,
      },
      secretKey,
      secretKey,
    );
  } catch (error) {
    throw safeCommitError(error);
  }
}

export async function getMarketplaceCsvImportCommit(jobId: string, commandId: string): Promise<CsvImportCommitReadModel | null> {
  const session = await getAdminSession();
  if (!session || !/^[0-9a-f-]{36}$/i.test(jobId) || !/^[0-9a-f-]{36}$/i.test(commandId)) return null;
  const organization = encodeURIComponent(session.profile.organization_id);
  const rows = await readApi<CsvImportCommitReadModel[]>(
    `import_commit_read_model?organization_id=eq.${organization}&import_job_id=eq.${encodeURIComponent(jobId)}&id=eq.${encodeURIComponent(commandId)}&select=*&limit=1`,
    session,
  );
  return rows[0] ?? null;
}

export async function getMarketplaceCsvImportEventResults(jobId: string, limit = 100, cursor: string | null = null): Promise<CsvImportPage<CsvImportEventResultReadModel>> {
  const session = await getAdminSession();
  if (!session || !/^[0-9a-f-]{36}$/i.test(jobId)) return { rows: [], nextCursor: null, hasMore: false };
  const organization = encodeURIComponent(session.profile.organization_id);
  const boundedLimit = Math.min(Math.max(limit, 1), 200);
  const filters = [`organization_id=eq.${organization}`, `import_job_id=eq.${encodeURIComponent(jobId)}`];
  if (cursor) filters.push(`created_at=gt.${encodeURIComponent(cursor)}`);
  const rows = await readApi<CsvImportEventResultReadModel[]>(
    `import_event_result_read_model?${filters.join("&")}&select=*&order=created_at.asc,id.asc&limit=${boundedLimit + 1}`,
    session,
  );
  const pageRows = rows.slice(0, boundedLimit);
  return { rows: pageRows, nextCursor: rows.length > boundedLimit ? pageRows.at(-1)?.created_at ?? null : null, hasMore: rows.length > boundedLimit };
}
