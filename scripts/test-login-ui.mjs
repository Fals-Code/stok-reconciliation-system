import assert from "node:assert/strict";
import {
  readFile,
} from "node:fs/promises";
import path from "node:path";

const root = process.cwd();

async function read(relativePath) {
  return readFile(
    path.join(
      root,
      relativePath,
    ),
    "utf8",
  );
}

const [
  packageSource,
  login,
  passwordInput,
  authActions,
  proxy,
] = await Promise.all([
  read("package.json"),
  read("src/app/login/page.tsx"),
  read(
    "src/app/login/password-input.tsx",
  ),
  read("src/app/auth-actions.ts"),
  read("src/proxy.ts"),
]);

const packageJson =
  JSON.parse(packageSource);

assert.equal(
  packageJson.scripts[
    "test:login-ui"
  ],
  "node scripts/test-login-ui.mjs",
  "package.json menyediakan test:login-ui",
);

assert.ok(
  login.includes(
    'data-login-layout="operator-login"',
  ) &&
    login.includes(
      'data-login-card="admin-auth"',
    ) &&
    login.includes(
      "Sistem Rekonsiliasi Stok",
    ) &&
    login.includes(
      'id="login-title"',
    ) &&
    login.includes(
      "Masuk",
    ),
  "Login memakai identity dan layout baru",
);

assert.ok(
  login.includes(
    'from "@/app/auth-actions"',
  ) &&
    login.includes(
      'from "@/lib/auth"',
    ) &&
    login.includes(
      "await getAdminSession()",
    ) &&
    login.includes(
      "redirect(returnTo)",
    ),
  "Login mempertahankan session dan safe return route contract",
);

assert.ok(
  login.includes(
    "action={loginAction}",
  ) &&
    login.includes(
      'name="email"',
    ) &&
    login.includes(
      'name="password"',
    ) &&
    login.includes(
      'autoComplete="email"',
    ) &&
    login.includes(
      'autoComplete="current-password"',
    ),
  "Field autentikasi tetap memakai contract server",
);

assert.ok(
  login.includes(
    "credentialError",
  ) &&
    login.includes(
      "Login belum berhasil",
    ) &&
    login.includes(
      "Email atau password tidak",
    ),
  "Login gagal menggunakan pesan generik",
);

assert.ok(
  authActions.includes(
    'CREDENTIALS_INVALID',
  ) &&
    !authActions.includes(
      "error: error.message",
    ) &&
    !authActions.includes(
      "errorMessage",
    ),
  "Auth action tidak memantulkan raw provider error",
);

assert.ok(
  authActions.includes(
    "signInWithPassword",
  ) &&
    authActions.includes("safeInternalRoute") &&
    authActions.includes("redirect(returnTo)"),
  "Auth mutation memulihkan safe internal GET route",
);

assert.ok(
  login.includes('name="returnTo"') &&
    login.includes("safeInternalRoute"),
  "Form login mempertahankan returnTo yang sudah divalidasi",
);

assert.ok(
  proxy.includes('request.method === "GET"') &&
    proxy.includes('request.method === "HEAD"') &&
    proxy.includes("loginUrl.searchParams.set(") &&
    proxy.includes('"returnTo"'),
  "Proxy hanya menyimpan route GET/HEAD dan tidak menyiapkan auto-replay mutation",
);

assert.ok(
  authActions.includes('params.set("returnTo", returnTo)') &&
    authActions.includes("loginFailure(") &&
    authActions.includes("returnTo,"),
  "Login failure tetap menyimpan safe returnTo untuk percobaan berikutnya",
);

assert.ok(
  passwordInput.includes(
    '"use client"',
  ) &&
    passwordInput.includes(
      "useState(false)",
    ) &&
    passwordInput.includes(
      "<IconButton",
    ) &&
    passwordInput.includes(
      "aria-pressed={visible}",
    ) &&
    passwordInput.includes(
      'type="button"',
    ) &&
    passwordInput.includes(
      "Tampilkan password",
    ) &&
    passwordInput.includes(
      "Sembunyikan password",
    ),
  "Password visibility accessible dan tidak submit form",
);

const sources = [
  login,
  passwordInput,
].join("\n");

for (const forbidden of [
  "GlowLab",
  "Stok Management",
  "Lupa password",
  "Buat akun",
  "Daftar",
  "<img",
  "data-login-visual",
  "LedgerPreview",
  "StockFlowIllustration",
  "TODO",
  "FIXME",
]) {
  assert.equal(
    sources.includes(forbidden),
    false,
    `Login tidak boleh mengandung ${forbidden}`,
  );
}

console.log(
  "Fresh login UI contract checks: PASS",
);
