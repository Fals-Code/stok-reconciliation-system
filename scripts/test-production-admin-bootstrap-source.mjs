import { readFile } from "node:fs/promises";

const checks = [];
function check(name, condition) {
  if (!condition) throw new Error(name);
  checks.push(name);
  console.log(`[PASS] ${name}`);
}

const [migration, script] = await Promise.all([
  readFile("supabase/migrations/20260814130812_production_reference_admin_bootstrap.sql", "utf8"),
  readFile("scripts/create-production-admin.mjs", "utf8"),
]);

check("Bootstrap Admin tidak menerima organisasi atau role dari pemanggil", /function api\.bootstrap_admin\(\s*p_user_id uuid,\s*p_email text,\s*p_display_name text default 'Admin'\s*\)/s.test(migration));
check("Bootstrap Admin dibatasi ke service role", /revoke all on function api\.bootstrap_admin\(uuid, text, text\) from public, anon, authenticated;\s*grant execute on function api\.bootstrap_admin\(uuid, text, text\) to service_role;/s.test(migration));
check("Bootstrap Admin memakai search_path tetap", /security definer\s*set search_path = pg_catalog, app, auth/s.test(migration));
check("Migration tidak memuat data stok atau demo", !/insert into (catalog\.products|catalog\.product_batches|inventory\.|marketplace\.|auth\.users)|demo\.clock\.fixed_at|simulator\.demo/i.test(migration));
check("Script memakai password hanya dari environment proses", /process\.env\.PRODUCTION_ADMIN_PASSWORD/.test(script) && !/args\.password|--password/.test(script));
check("Script menolak target lokal dan placeholder serta mewajibkan Supabase Cloud HTTPS", /url\.protocol !== "https:"/.test(script) && /endsWith\("\.supabase\.co"\)/.test(script) && /includes\("replace_me"\)/.test(script) && /includes\("placeholder"\)/.test(script));
check("Script mewajibkan APP_ENV production dan memanggil bootstrap netral", /env\.APP_ENV !== "production"/.test(script) && /rpc\/bootstrap_admin/.test(script));
check("Script tidak mencetak secret atau password", !/console\.log\([^\n]*(secretKey|password)/.test(script));
console.log(`Production Admin bootstrap source test PASS (${checks.length} checks)`);