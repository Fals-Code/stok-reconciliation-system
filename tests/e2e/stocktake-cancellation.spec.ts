import { expect, test, type Page } from "@playwright/test";

const ADMIN_EMAIL = process.env.PLAYWRIGHT_ADMIN_EMAIL ??
  "demo.admin@glowlab.invalid";

function adminPassword() {
  const password = process.env.PLAYWRIGHT_ADMIN_PASSWORD;
  if (!password) {
    throw new Error("PLAYWRIGHT_ADMIN_PASSWORD belum tersedia. Jalankan npm run test:stocktake-cancellation-browser.");
  }
  return password;
}

async function loginAsAdmin(page: Page) {
  await page.goto("/login", { waitUntil: "domcontentloaded" });
  await page.getByLabel("Email", { exact: true }).fill(ADMIN_EMAIL);
  await page.getByLabel("Password", { exact: true }).fill(adminPassword());
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/"),
    page.getByRole("button", { name: "Masuk", exact: true }).click(),
  ]);
}

async function expectNoRootOverflow(page: Page) {
  const state = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    viewportWidth: document.documentElement.clientWidth,
  }));
  expect(state.scrollWidth).toBeLessThanOrEqual(state.viewportWidth + 1);
}

async function expectStocktakeNavigationActive(page: Page) {
  const mobileTrigger = page.getByRole("button", {
    name: "Buka navigasi",
    exact: true,
  });

  if (await mobileTrigger.isVisible()) {
    const topbar = page.getByRole("banner");
    await expect(
      topbar.getByText("Stok Opname", { exact: true }),
    ).toBeVisible();
    return;
  }

  const desktopNavigation = page.getByRole("complementary", {
    name: "Navigasi desktop",
    exact: true,
  });
  const link = desktopNavigation.locator('a[href="/stocktakes"]');

  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute("aria-current", "page");
}

function stocktakeStatusMetric(page: Page) {
  return page.locator("article").filter({
    has: page.getByText("Status", { exact: true }),
  });
}

test("Admin membatalkan Hitung Stok draft secara aman dan terminal", async ({ page }, testInfo) => {
  test.setTimeout(60_000);
  const runtimeErrors: string[] = [];
  const serverFailures: string[] = [];
  page.on("pageerror", (error) => runtimeErrors.push(error.message));
  page.on("response", (response) => {
    if (response.status() >= 500) serverFailures.push(`${response.status()} ${new URL(response.url()).pathname}`);
  });

  await loginAsAdmin(page);
  await page.goto("/stocktakes/new", { waitUntil: "domcontentloaded" });
  await expectStocktakeNavigationActive(page);

  const title = `Smoke cancel ${testInfo.project.name} ${Date.now()}`;
  await page.getByLabel("Judul", { exact: true }).fill(title);
  await Promise.all([
    page.waitForURL((url) => /^\/stocktakes\/[^/]+$/.test(url.pathname)),
    page.getByRole("button", { name: "Buat sesi Draft", exact: true }).click(),
  ]);

  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toBeVisible();
  await expectStocktakeNavigationActive(page);

  const reason = page.getByLabel("Alasan pembatalan", { exact: true });
  await page.getByRole("checkbox", { name: /Saya memahami sesi dihentikan/ }).check();
  await page.getByRole("button", { name: "Batal Hitung Stok", exact: true }).click();
  await expect(reason).toBeFocused();
  await expect(stocktakeStatusMetric(page).getByText("Draft", { exact: true })).toBeVisible();

  const cancellationReason = "Fixture browser selesai diverifikasi.";
  await reason.fill(cancellationReason);
  await Promise.all([
    page.waitForURL((url) => /^\/stocktakes\/[^/]+$/.test(url.pathname) && (url.searchParams.get("success") ?? "").includes("dibatalkan tanpa mengubah stok.")),
    page.getByRole("button", { name: "Batal Hitung Stok", exact: true }).click(),
  ]);

  await expect(page.getByText(/dibatalkan tanpa mengubah stok\.$/)).toBeVisible();
  await expect(stocktakeStatusMetric(page).getByText("Dibatalkan", { exact: true })).toBeVisible();
  await expect(page.getByText(`Alasan: ${cancellationReason}`, { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /Validasi dan siapkan sesi|Mulai penghitungan|Simpan|Setujui|Posting/ })).toHaveCount(0);

  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(stocktakeStatusMetric(page).getByText("Dibatalkan", { exact: true })).toBeVisible();
  await expect(page.getByText(`Alasan: ${cancellationReason}`, { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toHaveCount(0);
  await expectNoRootOverflow(page);

  await page.getByRole("link", { name: "Kembali ke daftar", exact: true }).click();
  await page.waitForURL((url) => url.pathname === "/stocktakes");
  await expectStocktakeNavigationActive(page);
  await expectNoRootOverflow(page);
  expect(runtimeErrors).toEqual([]);
  expect(serverFailures).toEqual([]);
});
