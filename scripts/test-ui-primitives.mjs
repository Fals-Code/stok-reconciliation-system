import assert from "node:assert/strict";
import {
  readFile,
} from "node:fs/promises";
import path from "node:path";

const root = process.cwd();

async function read(relativePath) {
  return readFile(
    path.join(root, relativePath),
    "utf8",
  );
}

const [
  packageSource,
  globals,
  index,
  button,
  iconButton,
  controls,
  field,
  alert,
  statusBadge,
  emptyState,
] = await Promise.all([
  read("package.json"),
  read("src/app/globals.css"),
  read("src/components/ui/index.ts"),
  read("src/components/ui/button.tsx"),
  read("src/components/ui/icon-button.tsx"),
  read("src/components/ui/controls.tsx"),
  read("src/components/ui/field.tsx"),
  read("src/components/ui/alert.tsx"),
  read("src/components/ui/status-badge.tsx"),
  read("src/components/ui/empty-state.tsx"),
]);

const packageJson =
  JSON.parse(packageSource);

assert.equal(
  packageJson.scripts[
    "test:ui-primitives"
  ],
  "node scripts/test-ui-primitives.mjs",
);

for (const marker of [
  '@import "tailwindcss"',
  "--ui-canvas: #f7f8f6",
  "--ui-surface: #ffffff",
  "--ui-text: #18201e",
  "--ui-primary: #1f6f64",
  "--ui-warning: #b45309",
  "--ui-danger: #b42318",
  "--ui-focus: #2f8075",
  "Inter",
  "font-variant-numeric: tabular-nums",
]) {
  assert.ok(
    globals.includes(marker),
    `globals.css wajib memuat ${marker}`,
  );
}

assert.equal(
  globals.includes("Arial"),
  false,
  "Arial legacy tidak boleh kembali",
);

assert.equal(
  globals.includes("Courier New"),
  false,
  "Courier New legacy tidak boleh kembali",
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
  assert.ok(
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
  assert.ok(
    button.includes(`"${variant}"`),
    `Button menyediakan ${variant}`,
  );
}

assert.ok(
  button.includes(
    "aria-busy=",
  ) &&
    button.includes(
      "disabled={isDisabled}",
    ) &&
    button.includes(
      "min-h-[var(--ui-control-height)]",
    ),
  "Button memiliki loading, disabled, dan ukuran minimum",
);

assert.ok(
  iconButton.includes(
    "aria-label={label}",
  ) &&
    iconButton.includes(
      "h-[var(--ui-control-height)]",
    ) &&
    iconButton.includes(
      "w-[var(--ui-control-height)]",
    ),
  "IconButton memiliki accessible name dan target 44px",
);

assert.ok(
  controls.includes(
    'data-ui-control="input"',
  ) &&
    controls.includes(
      'data-ui-control="select"',
    ) &&
    controls.includes(
      'data-ui-control="textarea"',
    ) &&
    controls.includes(
      "aria-[invalid=true]:border-ui-danger",
    ),
  "Input, Select, dan Textarea memiliki semantics konsisten",
);

assert.ok(
  field.includes(
    '"aria-describedby"',
  ) &&
    field.includes(
      '"aria-invalid"',
    ) &&
    field.includes(
      "htmlFor={id}",
    ) &&
    field.includes(
      'role="alert"',
    ),
  "Field menghubungkan label, helper, dan error",
);

for (const tone of [
  "info",
  "success",
  "warning",
  "danger",
]) {
  assert.ok(
    alert.includes(`"${tone}"`),
    `Alert menyediakan tone ${tone}`,
  );
}

assert.ok(
  alert.includes(
    'tone === "danger"',
  ) &&
    alert.includes('"alert"') &&
    alert.includes('"status"'),
  "Alert membedakan alert dan status",
);

for (const tone of [
  "neutral",
  "selected",
  "warning",
  "danger",
]) {
  assert.ok(
    statusBadge.includes(`"${tone}"`),
    `StatusBadge menyediakan tone ${tone}`,
  );
}

assert.ok(
  statusBadge.includes(
    "{children}",
  ),
  "StatusBadge selalu membawa label tekstual",
);

assert.ok(
  emptyState.includes(
    "action?: ReactNode",
  ) &&
    emptyState.includes(
      "{action ? (",
    ),
  "EmptyState hanya menampilkan action nyata bila diberikan",
);

const source = [
  globals,
  index,
  button,
  iconButton,
  controls,
  field,
  alert,
  statusBadge,
  emptyState,
].join("\n");

for (const forbidden of [
  "TODO",
  "FIXME",
  "primary-button",
  "field-label",
  "status-pill",
]) {
  assert.equal(
    source.includes(forbidden),
    false,
    `Fondasi tidak boleh membawa legacy ${forbidden}`,
  );
}

console.log(
  "Fresh UI foundation contract checks: PASS",
);