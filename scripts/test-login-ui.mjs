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
] = await Promise.all([
  read("package.json"),
  read("src/app/login/page.tsx"),
  read(
    "src/app/login/password-input.tsx",
  ),
  read("src/app/auth-actions.ts"),
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
      'redirect("/")',
    ),
  "Login mempertahankan session dan redirect contract",
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
    authActions.includes(
      'redirect("/")',
    ),
  "Auth mutation contract tetap dipertahankan",
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