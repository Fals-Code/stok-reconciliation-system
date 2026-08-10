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
  primaryNavigation,
  settingsNavigation,
  getActiveNavHref,
  isNavItemActive,
} = await import(navigationModuleUrl);

// 1. Menu utama hanya area yang memang perlu dikenal user
assert.equal(primaryNavigation.length, 3, "Primary navigation harus memiliki 3 menu utama");
assert.equal(primaryNavigation[0].label, "Beranda");
assert.equal(primaryNavigation[0].href, "/");
assert.equal(primaryNavigation[1].label, "Stok");
assert.equal(primaryNavigation[1].href, "/products");
assert.equal(primaryNavigation[2].label, "Pesanan");
assert.equal(primaryNavigation[2].href, "/marketplace");

assert.equal(settingsNavigation.label, "Pengaturan");
assert.equal(settingsNavigation.href, "/settings");

// 2. Pembuktian route contextual mapping
assert.equal(getActiveNavHref("/"), "/");
assert.equal(getActiveNavHref("/products"), "/products");
assert.equal(getActiveNavHref("/products/product-123"), "/products");
assert.equal(getActiveNavHref("/products/product-123/batches/batch-456"), "/products");
assert.equal(getActiveNavHref("/receipts/new"), "/products");
assert.equal(getActiveNavHref("/manual-outbounds"), "/products");
assert.equal(getActiveNavHref("/stock-disposals"), "/products");
assert.equal(getActiveNavHref("/stocktakes"), "/products");
assert.equal(getActiveNavHref("/stocktakes/new"), "/products");
assert.equal(getActiveNavHref("/stock-issues"), "/products");
assert.equal(getActiveNavHref("/ledger"), "/products");
assert.equal(getActiveNavHref("/ledger/tx-123"), "/products");
assert.equal(getActiveNavHref("/entry-corrections"), "/products");

assert.equal(getActiveNavHref("/marketplace"), "/marketplace");
assert.equal(getActiveNavHref("/marketplace/order-123"), "/marketplace");
assert.equal(getActiveNavHref("/returns"), "/marketplace");
assert.equal(getActiveNavHref("/returns/return-123"), "/marketplace");

assert.equal(getActiveNavHref("/settings"), "/settings");
assert.equal(getActiveNavHref("/opening-balances"), "/settings");

assert.equal(getActiveNavHref("/route-tidak-dikenal"), null);

// 3. Pembuktian isNavItemActive helper
assert.equal(isNavItemActive("/", "/"), true);
assert.equal(isNavItemActive("/products", "/receipts/new"), true);
assert.equal(isNavItemActive("/marketplace", "/returns/return-123"), true);
assert.equal(isNavItemActive("/settings", "/opening-balances"), true);
assert.equal(isNavItemActive("/", "/products"), false);

// 4. Metadata Identity & content restriction assertions (dari Commit 01)
const layoutSource = await readFile(
  new URL("../src/app/layout.tsx", import.meta.url),
  "utf8",
);

assert.ok(
  layoutSource.includes("Sistem Rekonsiliasi Stok"),
  "Metadata layout wajib mencantumkan Sistem Rekonsiliasi Stok",
);

for (const forbidden of [
  "GlowLab Inventory",
  "Stok Management",
]) {
  assert.equal(
    layoutSource.includes(forbidden),
    false,
    `Root layout tidak boleh memakai ${forbidden}`,
  );
}

console.log("Navigation contract focused checks: PASS");
