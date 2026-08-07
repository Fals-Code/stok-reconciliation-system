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

const [
  packageJsonSource,
  index,
  button,
  iconButton,
  controls,
  field,
  statusBadge,
  alert,
  emptyState,
  login,
  passwordInput,
] = await Promise.all([
  read("package.json"),
  read("src/components/ui/index.ts"),
  read("src/components/ui/button.tsx"),
  read("src/components/ui/icon-button.tsx"),
  read("src/components/ui/controls.tsx"),
  read("src/components/ui/field.tsx"),
  read("src/components/ui/status-badge.tsx"),
  read("src/components/ui/alert.tsx"),
  read("src/components/ui/empty-state.tsx"),
  read("src/app/login/page.tsx"),
  read("src/app/login/password-input.tsx"),
]);

const packageJson =
  JSON.parse(packageJsonSource);

assert(
  packageJson.scripts?.[
    "test:ui-primitives"
  ] ===
    "node scripts/test-ui-primitives.mjs",
  "package.json menyediakan test:ui-primitives",
);

for (const exportName of [
  "Alert",
  "Button",
  "EmptyState",
  "Field",
  "IconButton",
  "Input",
  "Select",
  "Textarea",
  "StatusBadge",
]) {
  assert(
    index.includes(exportName),
    `UI barrel mengekspor ${exportName}`,
  );
}

for (const variant of [
  "primary",
  "secondary",
  "danger",
  "ghost",
]) {
  assert(
    button.includes(`"${variant}"`),
    `Button menyediakan variant ${variant}`,
  );
}

assert(
  button.includes(
    "min-h-[var(--ui-control-height)]",
  ) &&
    button.includes(
      "focus-visible:outline-ui-focus",
    ) &&
    button.includes(
      "disabled={isDisabled}",
    ) &&
    button.includes(
      "aria-busy={loading || undefined}",
    ),
  "Button memiliki ukuran, focus, disabled, dan loading semantics",
);

assert(
  iconButton.includes(
    'aria-label={label}',
  ) &&
    iconButton.includes(
      "h-[var(--ui-control-height)]",
    ) &&
    iconButton.includes(
      "w-[var(--ui-control-height)]",
    ) &&
    iconButton.includes(
      'type = "button"',
    ),
  "IconButton memiliki accessible name dan target minimum",
);

assert(
  controls.includes(
    "aria-[invalid=true]:border-ui-danger",
  ) &&
    controls.includes(
      "focus-visible:ring-ui-focus",
    ) &&
    controls.includes(
      "export function Input",
    ) &&
    controls.includes(
      "export function Select",
    ) &&
    controls.includes(
      "export function Textarea",
    ),
  "Control field menggunakan state focus/error yang konsisten",
);

assert(
  field.includes(
    '"aria-describedby": describedBy',
  ) &&
    field.includes(
      '"aria-invalid": error',
    ) &&
    field.includes(
      'role="alert"',
    ) &&
    field.includes(
      'htmlFor={id}',
    ),
  "Field menghubungkan label, description, dan error secara aksesibel",
);

for (const tone of [
  "neutral",
  "selected",
  "warning",
  "danger",
]) {
  assert(
    statusBadge.includes(
      `"${tone}"`,
    ),
    `StatusBadge menyediakan tone ${tone}`,
  );
}

assert(
  statusBadge.includes(
    "data-status-badge",
  ) &&
    statusBadge.includes(
      "{children}",
    ),
  "StatusBadge selalu membawa label/content",
);

for (const tone of [
  "info",
  "success",
  "warning",
  "danger",
]) {
  assert(
    alert.includes(`"${tone}"`),
    `Alert menyediakan tone ${tone}`,
  );
}

assert(
  alert.includes(
    'tone === "danger"',
  ) &&
    alert.includes('"alert"') &&
    alert.includes('"status"'),
  "Alert memakai semantics status/alert sesuai konteks",
);

assert(
  emptyState.includes(
    "title: ReactNode",
  ) &&
    emptyState.includes(
      "description?: ReactNode",
    ) &&
    emptyState.includes(
      "action?: ReactNode",
    ) &&
    emptyState.includes(
      "{action ? (",
    ),
  "EmptyState hanya menampilkan action nyata bila diberikan",
);

assert(
  login.includes(
    'from "@/components/ui"',
  ) &&
    login.includes("<Alert") &&
    login.includes("<Button") &&
    login.includes("<Field") &&
    login.includes("<Input"),
  "Login mengadopsi shared primitives sebagai representative page",
);

assert(
  passwordInput.includes(
    'from "@/components/ui"',
  ) &&
    passwordInput.includes(
      "<IconButton",
    ) &&
    passwordInput.includes(
      "<Input",
    ) &&
    passwordInput.includes(
      "aria-pressed={visible}",
    ),
  "PasswordInput memakai Input dan IconButton shared",
);

const sources = [
  index,
  button,
  iconButton,
  controls,
  field,
  statusBadge,
  alert,
  emptyState,
].join("\n");

for (const forbidden of [
  "TODO",
  "FIXME",
  "primary-button",
  "field-label",
  "status-pill",
]) {
  assert(
    !sources.includes(forbidden),
    `Shared primitives tidak membawa legacy ${forbidden}`,
  );
}

if (failures.length > 0) {
  console.error(
    `\n${failures.length} pemeriksaan UI primitives gagal.`,
  );
  process.exit(1);
}

console.log(
  "\nSemua shared UI primitive contract checks PASS.",
);