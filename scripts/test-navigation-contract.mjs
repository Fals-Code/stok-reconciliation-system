import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const navigationSourceUrl = new URL(
  "../src/app/app-shell/navigation.ts",
  import.meta.url,
);

const navigationSource = await readFile(
  navigationSourceUrl,
  "utf8",
);

const compiledNavigation = ts.transpileModule(
  navigationSource,
  {
    fileName: "navigation.ts",
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
      verbatimModuleSyntax: true,
    },
  },
).outputText;

const navigationModuleUrl =
  `data:text/javascript;base64,${Buffer.from(compiledNavigation).toString("base64")}`;

const {
  APP_NAV_SECTIONS,
  findActiveNavItem,
  getActiveNavHref,
  isNavItemActive,
} = await import(navigationModuleUrl);

const expectedRoutes = [
  "/",
  "/entry-corrections",
  "/ledger",
  "/manual-outbounds",
  "/marketplace",
  "/marketplace/import",
  "/notifications",
  "/notifications/operations",
  "/opening-balances",
  "/products",
  "/reconciliation",
  "/returns",
  "/stock-disposals",
  "/stocktakes",
  "/today",
];

const items = APP_NAV_SECTIONS.flatMap((section) =>
  section.items.map((item) => ({
    ...item,
    sectionLabel: section.label,
  })),
);

const actualRoutes = items
  .map((item) => item.href)
  .sort((left, right) => left.localeCompare(right));

assert.deepEqual(
  actualRoutes,
  expectedRoutes,
  "Seluruh tujuan navigasi lama harus tetap tersedia",
);

assert.equal(
  new Set(actualRoutes).size,
  actualRoutes.length,
  "Route navigasi tidak boleh duplikat",
);

assert.deepEqual(
  APP_NAV_SECTIONS.map((section) => section.label),
  [
    "Utama",
    "Pekerjaan Gudang",
    "Kontrol Stok",
    "Data & Sistem",
  ],
  "Navigasi dikelompokkan berdasarkan pekerjaan Admin",
);

for (const forbiddenLabel of [
  "Dashboard",
  "Ledger Explorer",
  "Notification Center",
  "Notification Operations",
]) {
  assert.equal(
    items.some((item) => item.label === forbiddenLabel),
    false,
    `Label teknis lama tidak boleh tersisa: ${forbiddenLabel}`,
  );
}

assert.equal(isNavItemActive("/", "/"), true);
assert.equal(isNavItemActive("/today", "/"), false);
assert.equal(
  isNavItemActive(
    "/marketplace/import",
    "/marketplace",
  ),
  true,
);

assert.equal(getActiveNavHref("/"), "/");
assert.equal(getActiveNavHref("/today"), "/today");
assert.equal(getActiveNavHref("/today/detail"), "/today");

assert.equal(
  getActiveNavHref("/marketplace"),
  "/marketplace",
);
assert.equal(
  getActiveNavHref("/marketplace/listings"),
  "/marketplace",
);
assert.equal(
  getActiveNavHref("/marketplace/import"),
  "/marketplace/import",
);
assert.equal(
  getActiveNavHref("/marketplace/import/job-123"),
  "/marketplace/import",
);

assert.equal(
  getActiveNavHref("/notifications"),
  "/notifications",
);
assert.equal(
  getActiveNavHref("/notifications/detail-123"),
  "/notifications",
);
assert.equal(
  getActiveNavHref("/notifications/operations"),
  "/notifications/operations",
);
assert.equal(
  getActiveNavHref(
    "/notifications/operations/outbox",
  ),
  "/notifications/operations",
);

assert.equal(
  getActiveNavHref("/route-tidak-dikenal"),
  null,
);

const marketplaceImport = findActiveNavItem(
  "/marketplace/import/job-123",
);

assert.equal(
  marketplaceImport?.sectionLabel,
  "Pekerjaan Gudang",
);
assert.equal(
  marketplaceImport?.item.label,
  "Impor Marketplace",
);

const notificationOperations = findActiveNavItem(
  "/notifications/operations/outbox",
);

assert.equal(
  notificationOperations?.sectionLabel,
  "Data & Sistem",
);
assert.equal(
  notificationOperations?.item.label,
  "Pemrosesan Notifikasi",
);

console.log("Navigation contract focused checks: PASS");
