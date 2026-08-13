import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import ts from "typescript";

async function source(relativePath) {
  return readFile(new URL(`../${relativePath}`, import.meta.url), "utf8");
}

async function exists(relativePath) {
  try {
    await access(new URL(`../${relativePath}`, import.meta.url));
    return true;
  } catch {
    return false;
  }
}

async function importTypeScript(relativePath, fileName) {
  const input = await source(relativePath);
  const output = ts.transpileModule(input, {
    fileName,
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
      verbatimModuleSyntax: true,
    },
  }).outputText;

  return import(
    `data:text/javascript;base64,${Buffer.from(output).toString("base64")}`
  );
}

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
assert.equal(getActiveNavHref("/reconciliation"), "/products");
assert.equal(getActiveNavHref("/ledger"), "/products");
assert.equal(getActiveNavHref("/ledger/tx-123"), "/products");
assert.equal(getActiveNavHref("/entry-corrections"), "/products");

assert.equal(getActiveNavHref("/marketplace"), "/marketplace");
assert.equal(getActiveNavHref("/marketplace/order-123"), "/marketplace");
assert.equal(getActiveNavHref("/marketplace/listings"), "/settings");
assert.equal(getActiveNavHref("/marketplace/import"), "/settings");
assert.equal(getActiveNavHref("/marketplace/import/job-123"), "/settings");
assert.equal(getActiveNavHref("/returns"), "/marketplace");
assert.equal(getActiveNavHref("/returns/return-123"), "/marketplace");

assert.equal(getActiveNavHref("/settings"), "/settings");
assert.equal(getActiveNavHref("/opening-balances"), "/settings");
assert.equal(getActiveNavHref("/notifications/operations"), "/settings");

assert.equal(getActiveNavHref("/route-tidak-dikenal"), null);

// 3. Pembuktian isNavItemActive helper
assert.equal(isNavItemActive("/", "/"), true);
assert.equal(isNavItemActive("/products", "/receipts/new"), true);
assert.equal(isNavItemActive("/marketplace", "/returns/return-123"), true);
assert.equal(isNavItemActive("/settings", "/opening-balances"), true);
assert.equal(isNavItemActive("/settings", "/marketplace/listings"), true);
assert.equal(isNavItemActive("/settings", "/marketplace/import/job-123"), true);
assert.equal(isNavItemActive("/marketplace", "/marketplace/order-123"), true);
assert.equal(isNavItemActive("/", "/products"), false);

// 4. Pengaturan menjadi pintu capability administratif, bukan menu utama baru
const settingsSource = await readFile(
  new URL("../src/app/settings/page.tsx", import.meta.url),
  "utf8",
);

for (const [label, href] of [
  ["Setup Stok Awal", "/opening-balances"],
  ["Mapping Produk Marketplace", "/marketplace/listings"],
  ["Import / Simulator Pesanan", "/marketplace/import"],
  ["Status &amp; Diagnostik Sistem", "/notifications/operations"],
]) {
  assert.ok(
    settingsSource.includes(label),
    `Settings harus menampilkan ${label}`,
  );
  assert.ok(
    settingsSource.includes(`href="${href}"`),
    `Settings harus menautkan ${label} ke ${href}`,
  );
}

for (const item of [...primaryNavigation, settingsNavigation]) {
  assert.equal(
    [
      "/opening-balances",
      "/marketplace/listings",
      "/marketplace/import",
      "/notifications/operations",
    ].includes(item.href),
    false,
    `${item.href} tidak boleh menjadi item primary navigation`,
  );
}

const capabilitySources = await Promise.all([
  readFile(new URL("../src/app/opening-balances/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../src/app/marketplace/listings/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../src/app/marketplace/import/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../src/app/marketplace/import/[jobId]/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../src/app/notifications/operations/page.tsx", import.meta.url), "utf8"),
]);

assert.ok(capabilitySources[0].includes('href="/settings"'));
assert.ok(capabilitySources[1].includes('href="/settings"'));
assert.ok(capabilitySources[2].includes('href="/settings"'));
assert.ok(capabilitySources[3].includes('href="/marketplace/import"'));
assert.ok(capabilitySources[4].includes('href="/settings"'));

// 5. Metadata Identity & content restriction assertions (dari Commit 01)
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

// 6. Inventory route aktual tetap lengkap dan compatibility route tetap aman.
const expectedPages = [
  "src/app/page.tsx",
  "src/app/login/page.tsx",
  "src/app/today/page.tsx",
  "src/app/products/page.tsx",
  "src/app/products/[productId]/page.tsx",
  "src/app/products/[productId]/batches/[batchId]/page.tsx",
  "src/app/receipts/new/page.tsx",
  "src/app/manual-outbounds/page.tsx",
  "src/app/stock-disposals/page.tsx",
  "src/app/stocktakes/page.tsx",
  "src/app/stocktakes/new/page.tsx",
  "src/app/stocktakes/[stocktakeId]/page.tsx",
  "src/app/stock-issues/page.tsx",
  "src/app/reconciliation/page.tsx",
  "src/app/ledger/page.tsx",
  "src/app/ledger/[transactionId]/page.tsx",
  "src/app/entry-corrections/page.tsx",
  "src/app/marketplace/page.tsx",
  "src/app/marketplace/[orderId]/page.tsx",
  "src/app/returns/page.tsx",
  "src/app/returns/[returnId]/page.tsx",
  "src/app/settings/page.tsx",
  "src/app/opening-balances/page.tsx",
  "src/app/marketplace/listings/page.tsx",
  "src/app/marketplace/import/page.tsx",
  "src/app/marketplace/import/[jobId]/page.tsx",
  "src/app/notifications/page.tsx",
  "src/app/notifications/operations/page.tsx",
];

for (const pagePath of expectedPages) {
  assert.equal(await exists(pagePath), true, `Route page harus ada: ${pagePath}`);
}

for (const [pagePath, destination] of [
  ["src/app/today/page.tsx", "/"],
  ["src/app/notifications/page.tsx", "/"],
]) {
  assert.ok(
    (await source(pagePath)).includes(`redirect("${destination}")`),
    `${pagePath} harus menjadi compatibility redirect ke ${destination}`,
  );
}

assert.ok(
  (await source("src/app/reconciliation/page.tsx")).includes("/stock-issues"),
  "/reconciliation harus tetap compatibility redirect ke /stock-issues",
);

// 7. Semua returnTo memakai validator internal yang sama dan dibatasi ke parent route.
const { isSafeInternalRoute, safeInternalRoute } = await importTypeScript(
  "src/lib/safe-internal-route.ts",
  "safe-internal-route.ts",
);

for (const unsafe of [
  "https://evil.example/path",
  "//evil.example/path",
  "javascript:alert(1)",
  "/products\\@evil.example/path",
  "/products\n/next",
  "/products\r/next",
]) {
  assert.equal(isSafeInternalRoute(unsafe), false, `${unsafe} harus ditolak`);
}

assert.equal(isSafeInternalRoute("/products?q=serum#stock-list"), true);
assert.equal(
  safeInternalRoute("/marketplace?q=ORD-1&status=OPEN", "/marketplace", {
    allowedPathnames: ["/marketplace"],
  }),
  "/marketplace?q=ORD-1&status=OPEN",
);
assert.equal(
  safeInternalRoute("/marketplace/import", "/marketplace", {
    allowedPathnames: ["/marketplace"],
  }),
  "/marketplace",
  "Detail pesanan tidak boleh kembali ke route Admin marketplace",
);

// 8. Context list -> detail -> mutation mempertahankan returnTo yang aman.
const contextualSources = Object.fromEntries(
  await Promise.all(
    [
      "src/app/marketplace/page.tsx",
      "src/app/marketplace/[orderId]/page.tsx",
      "src/app/marketplace/cancellations/actions.ts",
      "src/app/returns/page.tsx",
      "src/app/returns/[returnId]/page.tsx",
      "src/app/returns/actions.ts",
      "src/app/stocktakes/page.tsx",
      "src/app/stocktakes/[stocktakeId]/page.tsx",
      "src/app/stocktakes/actions.ts",
    ].map(async (file) => [file, await source(file)]),
  ),
);

for (const [file, body] of Object.entries(contextualSources)) {
  assert.ok(body.includes("returnTo"), `${file} harus mempertahankan returnTo`);
}

// 9. Notification Center bukan workspace utama, tetapi capability write tetap contextual.
assert.equal(
  await exists("src/app/notifications/actions.ts"),
  true,
  "Notification write actions tetap tersedia sebagai capability contextual",
);
assert.equal(
  await exists("scripts/test-notification-write-actions.mjs"),
  true,
  "Regression test notification write actions tetap tersedia",
);

const packageJson = JSON.parse(await source("package.json"));
assert.equal(
  packageJson.scripts["test:notification-write-actions"],
  "node scripts/test-notification-write-actions.mjs",
  "Package script notification write actions tetap tersedia",
);

const notificationCompatibility = await source(
  "src/app/notifications/page.tsx",
);
assert.match(
  notificationCompatibility,
  /redirect\(["']\/["']\)/,
  "/notifications tetap compatibility redirect ke Beranda",
);
assert.doesNotMatch(
  notificationCompatibility,
  /acknowledgeNotificationAction|setNotificationReadStateAction|revokeNotificationAcknowledgmentAction/,
  "/notifications tidak kembali menjadi Notification Center workspace",
);

const notificationOperations = await source(
  "src/app/notifications/operations/page.tsx",
);
assert.match(
  notificationOperations,
  /NotificationStatePanel/,
  "Diagnostics memasang contextual notification state capability",
);
assert.match(
  notificationOperations,
  /#notification-state/,
  "Diagnostics menyediakan navigation anchor untuk status notifikasi",
);

const notificationStatePanel = await source(
  "src/app/notifications/operations/notification-state-panel.tsx",
);
for (const actionName of [
  "setNotificationReadStateAction",
  "acknowledgeNotificationAction",
  "revokeNotificationAcknowledgmentAction",
]) {
  assert.match(
    notificationStatePanel,
    new RegExp(actionName),
    `${actionName} harus reachable melalui Diagnostics`,
  );
}

const notificationActions = await source(
  "src/app/notifications/actions.ts",
);
assert.match(
  notificationActions,
  /\/notifications\/operations#notification-state/,
  "Notification mutation kembali ke contextual Diagnostics state",
);
assert.match(
  notificationActions,
  /destination\.pathname !== "\/notifications\/operations"/,
  "Notification mutation membatasi return route ke Diagnostics",
);

const rootActions = await source("src/app/actions.ts");
for (const legacyAction of [
  "postReceiptAction",
  "reserveMarketplaceOrderAction",
  "advanceMarketplaceOrderAction",
  "createExpectedReturnAction",
  "confirmReturnReceiptAction",
  "inspectReturnAction",
  "markReturnLostAction",
]) {
  assert.equal(
    rootActions.includes(`export async function ${legacyAction}`),
    false,
    `${legacyAction} legacy tidak boleh diekspor dari root action module`,
  );
}
assert.ok(rootActions.includes("export async function runReconciliationAction"));

// 10. Failure state capability Admin tetap kembali ke Pengaturan/parent flow.
const listingAdminSource = await source("src/app/marketplace/listings/page.tsx");
const diagnosticsSource = await source("src/app/notifications/operations/page.tsx");
const importSource = await source("src/app/marketplace/import/page.tsx");
const importDetailSource = await source(
  "src/app/marketplace/import/[jobId]/page.tsx",
);

assert.ok(
  listingAdminSource.includes("Data listing gagal dimuat.") &&
    listingAdminSource.includes('href="/settings"'),
  "Failure mapping marketplace harus kembali ke Pengaturan",
);
assert.ok(
  diagnosticsSource.includes("Halaman operasi belum dapat dimuat.") &&
    diagnosticsSource.includes('href="/settings"'),
  "Failure diagnostics harus kembali ke Pengaturan",
);
for (const [file, body] of [
  ["src/app/marketplace/import/page.tsx", importSource],
  ["src/app/marketplace/import/[jobId]/page.tsx", importDetailSource],
]) {
  assert.ok(
    body.includes("try {") &&
      body.includes("catch") &&
      body.includes("Muat ulang") &&
      body.includes("Kembali"),
    `${file} harus memberi failure recovery tanpa HTTP 5xx`,
  );
}

for (const [file, body] of [
  ["src/app/marketplace/listings/page.tsx", listingAdminSource],
  ["src/app/marketplace/import/page.tsx", importSource],
  ["src/app/marketplace/import/[jobId]/page.tsx", importDetailSource],
  ["src/app/notifications/operations/page.tsx", diagnosticsSource],
]) {
  assert.ok(
    body.includes("<AppShell") && body.includes("requireAdminSession"),
    `${file} harus merender primary nav Pengaturan pada desktop/mobile`,
  );
}

console.log("Navigation contract focused checks: PASS");
