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

function primaryStockLink(page: Page) {
  return page.locator("nav[aria-label='Navigasi utama']")
    .getByRole("link", { name: "Stok", exact: true })
    .filter({ visible: true });
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
  await expect(primaryStockLink(page)).toHaveAttribute("aria-current", "page");

  const title = `Smoke cancel ${testInfo.project.name} ${Date.now()}`;
  await page.getByLabel("Nama hitung stok", { exact: true }).fill(title);
  await Promise.all([
    page.waitForURL((url) => /^\/stocktakes\/[^/]+$/.test(url.pathname)),
    page.getByRole("button", { name: "Buat Sesi", exact: true }).click(),
  ]);

  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toBeVisible();
  await expect(primaryStockLink(page)).toHaveAttribute("aria-current", "page");

  const reason = page.getByLabel("Alasan pembatalan", { exact: true });
  await page.getByRole("checkbox", { name: /Saya memahami sesi dihentikan/ }).check();
  await page.getByRole("button", { name: "Batal Hitung Stok", exact: true }).click();
  await expect(reason).toBeFocused();
  await expect(page.getByText("Belum Dimulai", { exact: true })).toBeVisible();

  const cancellationReason = "Fixture browser selesai diverifikasi.";
  await reason.fill(cancellationReason);
  const cancelButton = page.getByRole("button", {
    name: "Batal Hitung Stok",
    exact: true,
  });
  await Promise.all([
    page.waitForURL((url) => /^\/stocktakes\/[^/]+$/.test(url.pathname) && url.searchParams.get("notice") === "updated"),
    cancelButton.evaluate((button) => {
      if (!(button instanceof HTMLButtonElement)) {
        throw new Error("Cancellation control must be a button.");
      }
      button.click();
      button.click();
    }),
  ]);

  await expect(page.getByText("Hitung Stok diperbarui", { exact: true })).toBeVisible();
  await expect(page.getByText("Dibatalkan", { exact: true })).toBeVisible();
  await expect(page.getByText(`Alasan: ${cancellationReason}`, { exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /Siapkan|Mulai Hitung|Simpan Perubahan|Setujui|Posting/ })).toHaveCount(0);

  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(page.getByText("Dibatalkan", { exact: true })).toBeVisible();
  await expect(page.getByText(`Alasan: ${cancellationReason}`, { exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Batal Hitung Stok", exact: true })).toHaveCount(0);
  await expectNoRootOverflow(page);

  await page.getByRole("link", { name: /Kembali ke Hitung Stok$/ }).click();
  await page.waitForURL((url) => url.pathname === "/stocktakes");
  await expect(primaryStockLink(page)).toHaveAttribute("aria-current", "page");
  await expectNoRootOverflow(page);
  expect(runtimeErrors).toEqual([]);
  expect(serverFailures).toEqual([]);
});
