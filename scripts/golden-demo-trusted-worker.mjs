import { spawnSync } from "node:child_process";
import process from "node:process";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EVALUATOR_SIGNATURE = "notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)";
const EVALUATOR_PROCESS_NAME = "golden-demo-trusted-worker";
const EVALUATE_OPERATION = "EVALUATE_TIKTOK_CLAIM_NOTIFICATIONS";
const PROBE_OPERATION = "PROBE_TIKTOK_CLAIM_NOTIFICATION_WORKER";

function fail(code) {
  throw new Error(code);
}

function isIsoTimestamp(value) {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/i.test(value)
    && Number.isFinite(Date.parse(value));
}

function sqlLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function parseInput(raw) {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    fail("GOLDEN_TRUSTED_WORKER_INPUT_INVALID");
  }

  if (!input || typeof input !== "object" || Array.isArray(input)) {
    fail("GOLDEN_TRUSTED_WORKER_INPUT_INVALID");
  }

  if (input.operation === PROBE_OPERATION) {
    if (Object.keys(input).length !== 1) fail("GOLDEN_TRUSTED_WORKER_INPUT_INVALID");
    return { operation: PROBE_OPERATION };
  }

  const expectedKeys = ["operation", "organizationId", "idempotencyKey", "observedAt", "processName"].sort();
  const actualKeys = Object.keys(input).sort();
  if (
    input.operation !== EVALUATE_OPERATION
    || actualKeys.length !== expectedKeys.length
    || actualKeys.some((key, index) => key !== expectedKeys[index])
    || !UUID_PATTERN.test(String(input.organizationId ?? ""))
    || typeof input.idempotencyKey !== "string"
    || !input.idempotencyKey.trim()
    || input.idempotencyKey.length > 200
    || !isIsoTimestamp(input.observedAt)
    || input.processName !== EVALUATOR_PROCESS_NAME
  ) {
    fail("GOLDEN_TRUSTED_WORKER_INPUT_INVALID");
  }

  return {
    operation: EVALUATE_OPERATION,
    organizationId: input.organizationId,
    idempotencyKey: input.idempotencyKey,
    // Preserve the caller's validated timestamptz verbatim.  Converting through
    // Date loses sub-millisecond precision and can move an exact deadline-stage
    // invocation to just before its threshold.
    observedAt: input.observedAt,
    processName: EVALUATOR_PROCESS_NAME,
  };
}

function resolveLocalDbContainer() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.status !== 0) fail("GOLDEN_TRUSTED_WORKER_DB_NOT_FOUND");

  const candidates = String(result.stdout ?? "")
    .split(/\r?\n/)
    .map((name) => name.trim())
    .filter((name) => /^supabase_db_[A-Za-z0-9_-]+$/.test(name));

  if (candidates.length === 0) fail("GOLDEN_TRUSTED_WORKER_DB_NOT_FOUND");
  if (candidates.length !== 1) fail("GOLDEN_TRUSTED_WORKER_DB_AMBIGUOUS");
  return candidates[0];
}

function runFixedSql(container, input) {
  const privilegeCheck = `
do $$
begin
  if current_user <> 'service_role'
    or not has_function_privilege(current_user, ${sqlLiteral(EVALUATOR_SIGNATURE)}, 'EXECUTE') then
    raise exception using errcode = 'P0001', message = 'GOLDEN_TRUSTED_WORKER_ROLE_INVALID';
  end if;
end
$$;`;
  const evaluatorSql = input.operation === PROBE_OPERATION
    ? `select jsonb_build_object(
      'ok', true,
      'operation', ${sqlLiteral(PROBE_OPERATION)},
      'role', current_user,
      'privilege', has_function_privilege(current_user, ${sqlLiteral(EVALUATOR_SIGNATURE)}, 'EXECUTE')
    );`
    : `select notification.evaluate_tiktok_claim_deadlines(
      ${sqlLiteral(input.organizationId)}::uuid,
      ${sqlLiteral(input.idempotencyKey)},
      ${sqlLiteral(input.observedAt)}::timestamptz,
      ${sqlLiteral(EVALUATOR_PROCESS_NAME)}
    );`;
  const sql = `begin; set local role service_role;${privilegeCheck}\n${evaluatorSql}\ncommit;`;
  const result = spawnSync(
    "docker",
    ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"],
    { input: sql, encoding: "utf8", windowsHide: true },
  );
  if (result.status !== 0) {
    const code = String(result.stderr ?? "").includes("GOLDEN_TRUSTED_WORKER_ROLE_INVALID")
      ? "GOLDEN_TRUSTED_WORKER_ROLE_INVALID"
      : "GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED";
    fail(code);
  }
  const jsonLine = String(result.stdout ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .findLast((line) => line.startsWith("{"));
  if (!jsonLine) fail("GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED");
  try {
    return JSON.parse(jsonLine);
  } catch {
    fail("GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED");
  }
}

function sanitizeOutput(input, payload) {
  if (input.operation === PROBE_OPERATION) {
    return {
      ok: payload?.ok === true,
      operation: PROBE_OPERATION,
      role: payload?.role === "service_role" ? "service_role" : null,
      evaluatorPrivilege: payload?.privilege === true,
      mutationCount: 0,
    };
  }
  return {
    ok: true,
    operation: EVALUATE_OPERATION,
    action: typeof payload?.action === "string" ? payload.action : null,
    ruleRunId: UUID_PATTERN.test(String(payload?.ruleRunId ?? "")) ? payload.ruleRunId : null,
    status: typeof payload?.status === "string" ? payload.status : null,
    evaluatedCount: Number.isSafeInteger(payload?.evaluatedCount) ? payload.evaluatedCount : null,
    createdCount: Number.isSafeInteger(payload?.createdCount) ? payload.createdCount : null,
    updatedCount: Number.isSafeInteger(payload?.updatedCount) ? payload.updatedCount : null,
    resolvedCount: Number.isSafeInteger(payload?.resolvedCount) ? payload.resolvedCount : null,
    stockEffectCode: typeof payload?.stockEffectCode === "string" ? payload.stockEffectCode : null,
  };
}

try {
  const input = parseInput(await new Promise((resolve, reject) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { raw += chunk; });
    process.stdin.on("end", () => resolve(raw));
    process.stdin.on("error", reject);
  }));
  const payload = runFixedSql(resolveLocalDbContainer(), input);
  process.stdout.write(`${JSON.stringify(sanitizeOutput(input, payload))}\n`);
} catch (error) {
  const code = error instanceof Error && /^GOLDEN_TRUSTED_WORKER_[A-Z_]+$/.test(error.message)
    ? error.message
    : "GOLDEN_TRUSTED_WORKER_EXECUTION_FAILED";
  process.stdout.write(`${JSON.stringify({ ok: false, error: code })}\n`);
  process.exitCode = 1;
}
