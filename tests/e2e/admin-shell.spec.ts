import {
  expect,
  test,
  type Page,
} from "@playwright/test";

const ADMIN_EMAIL =
  process.env.PLAYWRIGHT_ADMIN_EMAIL ??
  "demo.admin@glowlab.invalid";

function getAdminPassword() {
  const password =
    process.env.PLAYWRIGHT_ADMIN_PASSWORD;

  if (!password) {
    throw new Error(
      "PLAYWRIGHT_ADMIN_PASSWORD belum tersedia. " +
        "Jalankan test melalui npm run test:admin-shell-browser.",
    );
  }

  return password;
}

async function loginAsAdmin(page: Page) {
  await page.goto("/login", {
    waitUntil: "domcontentloaded",
  });

  await page
    .getByLabel("Email", { exact: true })
    .fill(ADMIN_EMAIL);

  await page
    .getByLabel("Password", { exact: true })
    .fill(getAdminPassword());

  await Promise.all([
    page.waitForURL(
      (url) => url.pathname === "/",
      {
        timeout: 30_000,
      },
    ),
    page
      .getByRole("button", {
        name: "Masuk",
        exact: true,
      })
      .click(),
  ]);

  await expect(
    page.getByRole("link", { name: "Lewati ke konten utama" })
  ).toBeAttached();
}

test(
  "shell desktop memiliki navigasi utama dan active state yang benar",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan visual dan interaksi khusus desktop.",
    );

    const runtimeErrors: string[] = [];
    page.on("pageerror", (err) => {
      runtimeErrors.push(err.message);
    });

    await loginAsAdmin(page);

    // 1. Desktop sidebar navigation sidebar visible
    const sidebar = page.locator("aside");
    await expect(sidebar).toBeVisible();

    // 2. Primary & Settings navigation links exist
    const homeLink = sidebar.getByRole("link", { name: "Beranda", exact: true });
    const stockLink = sidebar.getByRole("link", { name: "Stok", exact: true });
    const orderLink = sidebar.getByRole("link", { name: "Pesanan", exact: true });
    const settingsLink = sidebar.getByRole("link", { name: "Pengaturan", exact: true });

    await expect(homeLink).toBeVisible();
    await expect(stockLink).toBeVisible();
    await expect(orderLink).toBeVisible();
    await expect(settingsLink).toBeVisible();

    // 3. Profile details displayed statically in sidebar
    await expect(sidebar.getByText("Sistem Rekonsiliasi Stok")).toBeVisible();
    await expect(sidebar.getByText("Operasional gudang")).toBeVisible();

    // 4. Default active navigation state on '/'
    await expect(homeLink).toHaveAttribute("aria-current", "page");
    await expect(stockLink).not.toHaveAttribute("aria-current");

    // 5. Navigation interaction updates URL and active tab
    await stockLink.click();
    await page.waitForURL((url) => url.pathname === "/products");
    await expect(stockLink).toHaveAttribute("aria-current", "page");
    await expect(homeLink).not.toHaveAttribute("aria-current");

    // 6. No relevant console or page errors
    expect(runtimeErrors).toEqual([]);
  },
);

test(
  "shell mobile merender bottom navigation bar",
  async ({ page, isMobile }) => {
    test.skip(
      !Boolean(isMobile),
      "Pemeriksaan bottom navigation khusus mobile.",
    );

    await loginAsAdmin(page);

    // Mobile header is visible
    await expect(page.locator("header")).toBeVisible();

    // Mobile bottom navigation contains 4 links
    const bottomNav = page.locator("nav[aria-label='Navigasi utama'].lg\\:hidden");
    await expect(bottomNav).toBeVisible();

    const homeLink = bottomNav.getByRole("link", { name: "Beranda", exact: true });
    const stockLink = bottomNav.getByRole("link", { name: "Stok", exact: true });
    const orderLink = bottomNav.getByRole("link", { name: "Pesanan", exact: true });
    const settingsLink = bottomNav.getByRole("link", { name: "Pengaturan", exact: true });

    await expect(homeLink).toBeVisible();
    await expect(stockLink).toBeVisible();
    await expect(orderLink).toBeVisible();
    await expect(settingsLink).toBeVisible();
  },
);

test(
  "keyboard navigation skip-link dan focus basic bekerja",
  async ({ page }) => {
    await loginAsAdmin(page);

    await page.goto("/", {
      waitUntil: "domcontentloaded",
    });

    // Press Tab to focus Skip Link
    await page.keyboard.press("Tab");

    const skipLink = page.getByRole("link", {
      name: "Lewati ke konten utama",
    });
    await expect(skipLink).toBeFocused();

    // Press Enter on skip link and ensure main content area receives focus
    await page.keyboard.press("Enter");
    const mainContent = page.locator("#main-content");
    await expect(mainContent).toBeFocused();
  },
);

test(
  "Pengaturan membuka capability administratif tanpa menambah primary navigation",
  async ({ page }) => {
    const runtimeErrors: string[] = [];
    const serverFailures: string[] = [];

    page.on("console", (message) => {
      if (message.type() === "error") {
        runtimeErrors.push(`${new URL(page.url()).pathname}: ${message.text()}`);
      }
    });
    page.on("pageerror", (error) => {
      runtimeErrors.push(error.message);
    });
    page.on("response", (response) => {
      if (response.status() >= 500) {
        serverFailures.push(`${response.status()} ${response.url()}`);
      }
    });

    await loginAsAdmin(page);
    await page.goto("/settings", {
      waitUntil: "domcontentloaded",
    });

    const settingsLink = page
      .locator("nav[aria-label='Navigasi utama']")
      .getByRole("link", { name: "Pengaturan", exact: true })
      .filter({ visible: true });

    await expect(settingsLink).toHaveAttribute("aria-current", "page");

    for (const [label, href] of [
      ["Setup Stok Awal", "/opening-balances"],
      ["Mapping Produk Marketplace", "/marketplace/listings"],
      ["Import / Simulator Pesanan", "/marketplace/import"],
      ["Status & Diagnostik Sistem", "/notifications/operations"],
    ] as const) {
      await expect(
        page.getByRole("link", { name: new RegExp(`^${label}`) }),
      ).toHaveAttribute("href", href);
    }

    for (const href of [
      "/opening-balances",
      "/marketplace/listings",
      "/marketplace/import",
      "/notifications/operations",
    ]) {
      await expect(
        page.locator(`nav[aria-label='Navigasi utama'] a[href='${href}']`),
      ).toHaveCount(0);
    }

    const administrativeFlows = [
      ["Setup Stok Awal", "/opening-balances"],
      ["Mapping Produk Marketplace", "/marketplace/listings"],
      ["Import / Simulator Pesanan", "/marketplace/import"],
    ] as const;

    for (const [label, pathname] of administrativeFlows) {
      await page.getByRole("link", { name: new RegExp(`^${label}`) }).click();
      await page.waitForURL((url) => url.pathname === pathname);

      const overflowState = await page.evaluate(() => {
        const viewportWidth = document.documentElement.clientWidth;
        const candidates = Array.from(
          document.querySelectorAll<HTMLElement>("body *"),
        )
          .filter(
            (element) =>
              element.getBoundingClientRect().right > viewportWidth + 1,
          )
          .slice(0, 10)
          .map((element) => ({
            className: element.className,
            tagName: element.tagName,
            text: element.textContent?.trim().slice(0, 80) ?? "",
          }));

        return {
          candidates,
          rootScrollWidth: document.documentElement.scrollWidth,
          viewportWidth,
        };
      });

      expect(
        overflowState.rootScrollWidth,
        JSON.stringify(overflowState.candidates),
      ).toBeLessThanOrEqual(overflowState.viewportWidth + 1);

      await page.reload({ waitUntil: "domcontentloaded" });
      await expect(
        page.getByRole("link", { name: "Kembali ke Pengaturan", exact: true }),
      ).toBeVisible();
      await page
        .getByRole("link", { name: "Kembali ke Pengaturan", exact: true })
        .click();
      await page.waitForURL((url) => url.pathname === "/settings");
    }

    expect(runtimeErrors).toEqual([]);
    expect(serverFailures).toEqual([]);
  },
);

test(
  "route contextual mengaktifkan parent menu yang benar secara visual",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan parent activation khusus desktop.",
    );

    await loginAsAdmin(page);

    const sidebar = page.locator("aside");
    const stockLink = sidebar.getByRole("link", { name: "Stok", exact: true });
    const orderLink = sidebar.getByRole("link", { name: "Pesanan", exact: true });
    const settingsLink = sidebar.getByRole("link", { name: "Pengaturan", exact: true });

    // Goto /receipts/new -> should light up 'Stok'
    await page.goto("/receipts/new", { waitUntil: "domcontentloaded" });
    await expect(stockLink).toHaveAttribute("aria-current", "page");

    // Goto /returns -> should light up 'Pesanan'
    await page.goto("/returns", { waitUntil: "domcontentloaded" });
    await expect(orderLink).toHaveAttribute("aria-current", "page");

    // Goto /opening-balances -> should light up 'Pengaturan'
    await page.goto("/opening-balances", { waitUntil: "domcontentloaded" });
    await expect(settingsLink).toHaveAttribute("aria-current", "page");
  },
);

test(
  "bebas dari horizontal overflow di layout utama",
  async ({ page }) => {
    await loginAsAdmin(page);

    const noHorizontalOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1;
    });

    expect(noHorizontalOverflow).toBe(true);
  },
);