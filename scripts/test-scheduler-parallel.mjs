import { spawn, spawnSync } from "node:child_process";

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
  console.log(`[PASS] ${message}`);
}

function containerName() {
  const result = spawnSync(
    "docker",
    ["ps", "--format", "{{.Names}}"],
    { encoding: "utf8", windowsHide: true },
  );
  if (result.status !== 0) fail("Docker Supabase lokal tidak dapat diperiksa.");
  const name = result.stdout
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => value.startsWith("supabase_db_"));
  if (!name) fail("Container database Supabase lokal tidak ditemukan.");
  return name;
}

function sql(container, statement) {
  const result = spawnSync(
    "docker",
    ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1"],
    { input: statement, encoding: "utf8", windowsHide: true },
  );
  if (result.status !== 0) fail(`SQL scheduler gagal: ${result.stderr || result.stdout}`);
  return result.stdout.trim();
}

function concurrentSql(container, statement) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "docker",
      ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1"],
      { windowsHide: true },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code !== 0) reject(new Error(`Concurrent SQL gagal: ${stderr || stdout}`));
      else resolve(stdout.trim());
    });
    child.stdin.end(statement);
  });
}

function stockSnapshot(container) {
  const output = sql(container, `
select jsonb_build_object(
  'transactions', (select count(*) from inventory.stock_transactions),
  'ledger', (select count(*) from inventory.stock_ledger_entries),
  'positions', (select count(*) from inventory.stock_product_positions),
  'reservations', (select count(*) from inventory.stock_reservations)
)::text;
`);
  return JSON.parse(output.split(/\r?\n/).findLast((line) => line.startsWith("{")) ?? "null");
}

const container = containerName();
const before = stockSnapshot(container);
const slot = new Date(Date.now() + 37 * 24 * 60 * 60 * 1000);
slot.setUTCSeconds(0, 0);
const isoSlot = slot.toISOString();
const literal = `'${isoSlot.replaceAll("'", "''")}'::timestamptz`;
const statement = `select scheduler.run_job_at('NOTIFICATION_OUTBOX', ${literal})::text;`;

try {
  const [first, second] = await Promise.all([
    concurrentSql(container, statement),
    concurrentSql(container, statement),
  ]);
  const results = [first, second].map((output) => JSON.parse(output.split(/\r?\n/).findLast((line) => line.startsWith("{")) ?? "null"));
  const actions = results.map((result) => result?.action).sort();
  assert(actions.join(",") === "EXECUTED,REPLAYED", "Dua trigger slot sama hanya mendelegasikan satu kali.");
  const runCount = Number(sql(container, `select count(*) from scheduler.job_runs where job_code='NOTIFICATION_OUTBOX' and scope_key='GLOBAL' and scheduled_slot=${literal};`));
  assert(runCount === 1, "Unique scheduler slot menahan eksekusi konkuren kedua.");
  assert(JSON.stringify(stockSnapshot(container)) === JSON.stringify(before), "Trigger scheduler konkuren tetap stock-neutral.");
} finally {
  sql(container, `delete from scheduler.job_runs where job_code='NOTIFICATION_OUTBOX' and scope_key='GLOBAL' and scheduled_slot=${literal};`);
}