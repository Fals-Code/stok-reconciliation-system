import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const failures = [];

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
    console.error(`[FAIL] ${message}`);
    return;
  }

  console.log(`[PASS] ${message}`);
}

async function read(relativePath) {
  return readFile(
    path.join(root, relativePath),
    "utf8",
  );
}

const packageJson =
  JSON.parse(
    await read("package.json"),
  );

const login =
  await read(
    "src/app/login/page.tsx",
  );

const passwordInput =
  await read(
    "src/app/login/password-input.tsx",
  );

const sources =
  `${login}\n${passwordInput}`;

assert(
  packageJson.scripts?.["test:login-ui"] ===
    "node scripts/test-login-ui.mjs",
  "package.json menyediakan test:login-ui",
);

assert(
  login.includes(
    'data-login-layout="simple-admin-login"',
  ) &&
    login.includes(
      'data-login-card="admin-auth"',
    ) &&
    /id="login-title"[\s\S]*?>\s*Masuk\s*<\/h1>/.test(
      login,
    ) &&
    login.includes(
      "Gunakan akun Admin gudang.",
    ),
  "Login tetap memakai form tunggal yang sederhana",
);

assert(
  login.includes(
    'import { loginAction } from "@/app/auth-actions";',
  ) &&
    login.includes(
      'import { PasswordInput } from "@/app/login/password-input";',
    ) &&
    login.includes(
      'from "@/components/ui";',
    ) &&
    login.includes(
      'import { getAdminSession } from "@/lib/auth";',
    ),
  "Login memakai auth contract dan shared UI primitives",
);

assert(
  login.includes(
    "const session = await getAdminSession();",
  ) &&
    login.includes(
      'redirect("/");',
    ),
  "Admin yang sudah login diarahkan ke aplikasi",
);

assert(
  login.includes(
    "action={loginAction}",
  ) &&
    login.includes(
      'aria-label="Masuk ke Stok Management"',
    ) &&
    login.includes(
      'autoComplete="email"',
    ) &&
    login.includes(
      'autoComplete="current-password"',
    ) &&
    login.includes(
      'type="submit"',
    ),
  "Form mempertahankan kontrak autentikasi",
);

assert(
  login.includes(
    'feedback.error ===',
  ) &&
    login.includes(
      '"Sesi Admin diperlukan."',
    ) &&
    login.includes(
      "errorMessage ? (",
    ) &&
    login.includes(
      'tone="danger"',
    ) &&
    login.includes(
      "feedback.message ? (",
    ) &&
    login.includes(
      'tone="success"',
    ),
  "Entry tanpa sesi tetap netral dan feedback nyata terlihat",
);

assert(
  login.includes(
    '<Field',
  ) &&
    login.includes(
      'id="login-email"',
    ) &&
    login.includes(
      'id="login-password"',
    ) &&
    login.includes(
      "<Input",
    ) &&
    login.includes(
      "<PasswordInput",
    ),
  "Login memakai shared Field tanpa mengubah nama input",
);

assert(
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
      'aria-pressed={visible}',
    ) &&
    passwordInput.includes(
      'visible\n            ? "Sembunyikan password"',
    ) &&
    passwordInput.includes(
      'type="button"',
    ),
  "Tombol tampilkan password tetap aksesibel dan tidak submit form",
);

for (const forbidden of [
  "Lupa password",
  "Buat akun",
  "<img",
  "lg:grid-cols",
  "data-login-visual",
  "LedgerPreview",
  "StockFlowIllustration",
  "InventoryCurveDivider",
  "Setiap pergerakan tercatat dan dapat ditelusuri.",
  "Stok jelas. Keputusan cepat.",
  "primary-button",
  "field-label",
  "TODO",
  "FIXME",
]) {
  assert(
    !sources.includes(forbidden),
    `Login tidak mengandung ${forbidden}`,
  );
}

if (failures.length > 0) {
  console.error(
    `\n${failures.length} pemeriksaan login gagal.`,
  );
  process.exit(1);
}

console.log(
  "\nSemua login UI contract checks PASS.",
);