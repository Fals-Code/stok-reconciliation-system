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

async function expectNoRootOverflow(page: Page) {
  const overflow = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    viewportWidth: document.documentElement.clientWidth,
  }));

  expect(overflow.scrollWidth).toBeLessThanOrEqual(
    overflow.viewportWidth + 1,
  );
}

function visiblePrimaryNavLink(page: Page, name: string) {
  return page
    .locator("nav[aria-label='Navigasi utama']")
    .getByRole("link", { name, exact: true })
    .filter({ visible: true });
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
    const sidebar = page.locator("aside").filter({
      has: page.locator("nav[aria-label='Navigasi utama']"),
    });
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
    await expect(page.locator("header.lg\\:hidden")).toBeVisible();

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
      ["Import Pesanan", "/marketplace/import"],
      ["Simulator Pesanan", "/marketplace/simulator"],
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
      "/marketplace/simulator",
      "/notifications/operations",
    ]) {
      await expect(
        page.locator(`nav[aria-label='Navigasi utama'] a[href='${href}']`),
      ).toHaveCount(0);
    }

    const administrativeFlows = [
      ["Setup Stok Awal", "/opening-balances"],
      ["Mapping Produk Marketplace", "/marketplace/listings"],
      ["Import Pesanan", "/marketplace/import"],
      ["Simulator Pesanan", "/marketplace/simulator"],
      ["Status & Diagnostik Sistem", "/notifications/operations"],
    ] as const;

    for (const [label, pathname] of administrativeFlows) {
      await page.getByRole("link", { name: new RegExp(`^${label}`) }).click();
      await page.waitForURL((url) => url.pathname === pathname);

      await expect(
        visiblePrimaryNavLink(page, "Pengaturan"),
      ).toHaveAttribute("aria-current", "page");

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
        page.getByRole("link", { name: /Kembali ke Pengaturan$/ }),
      ).toBeVisible();
      await page
        .getByRole("link", { name: /Kembali ke Pengaturan$/ })
        .click();
      await page.waitForURL((url) => url.pathname === "/settings");
    }

    expect(runtimeErrors).toEqual([]);
    expect(serverFailures).toEqual([]);
  },
);

test(
  "login mempertahankan route dan query internal setelah autentikasi",
  async ({ page }) => {
    const target = "/marketplace?status=OPEN";

    await page.goto(target, { waitUntil: "domcontentloaded" });
    await page.waitForURL((url) => url.pathname === "/login");

    const loginUrl = new URL(page.url());
    expect(loginUrl.searchParams.get("returnTo")).toBe(target);

    await page.getByLabel("Email", { exact: true }).fill(ADMIN_EMAIL);
    await page
      .getByLabel("Password", { exact: true })
      .fill(getAdminPassword());
    await page.getByRole("button", { name: "Masuk", exact: true }).click();
    await page.waitForURL((url) => (
      url.pathname === "/marketplace" &&
      url.searchParams.get("status") === "OPEN"
    ));

    await page.reload({ waitUntil: "domcontentloaded" });
    expect(new URL(page.url()).searchParams.get("status")).toBe("OPEN");
    await expect(
      visiblePrimaryNavLink(page, "Pesanan"),
    ).toHaveAttribute("aria-current", "page");
  },
);

test(
  "route kerja utama dan administratif tetap reachable di desktop dan mobile",
  async ({ page }) => {
    const runtimeErrors: string[] = [];
    const serverFailures: string[] = [];

    page.on("pageerror", (error) => runtimeErrors.push(error.message));
    page.on("response", (response) => {
      if (response.status() >= 500) {
        serverFailures.push(`${response.status()} ${response.url()}`);
      }
    });

    await loginAsAdmin(page);

    for (const [pathname, navName] of [
      ["/", "Beranda"],
      ["/products", "Stok"],
      ["/ledger", "Stok"],
      ["/stock-issues", "Stok"],
      ["/stocktakes", "Stok"],
      ["/marketplace", "Pesanan"],
      ["/returns", "Pesanan"],
      ["/settings", "Pengaturan"],
      ["/opening-balances", "Pengaturan"],
      ["/marketplace/listings", "Pengaturan"],
      ["/marketplace/import", "Pengaturan"],
      ["/notifications/operations", "Pengaturan"],
    ] as const) {
      const response = await page.goto(pathname, {
        waitUntil: "domcontentloaded",
      });

      expect(response?.status(), pathname).toBeLessThan(500);
      await expect(
        visiblePrimaryNavLink(page, navName),
      ).toHaveAttribute("aria-current", "page");
      await expectNoRootOverflow(page);
    }

    expect(runtimeErrors).toEqual([]);
    expect(serverFailures).toEqual([]);
  },
);

test(
  "compatibility route tetap mengarah ke workspace final",
  async ({ page }) => {
    await loginAsAdmin(page);

    await page.goto("/today", { waitUntil: "domcontentloaded" });
    await page.waitForURL((url) => url.pathname === "/");

    await page.goto("/notifications", { waitUntil: "domcontentloaded" });
    await page.waitForURL((url) => url.pathname === "/");

    await page.goto("/reconciliation?status=MISMATCH", {
      waitUntil: "domcontentloaded",
    });
    await page.waitForURL((url) => (
      url.pathname === "/stock-issues" &&
      url.searchParams.get("status") === "MISMATCH"
    ));
    await expect(
      visiblePrimaryNavLink(page, "Stok"),
    ).toHaveAttribute("aria-current", "page");
  },
);

test(
  "detail import dan Retur dibuka bila fixture read-only tersedia",
  async ({ page }, testInfo) => {
    await loginAsAdmin(page);

    for (const flow of [
      {
        list: "/marketplace/import",
        selector: "main a[href^='/marketplace/import/']:not([href='/marketplace/import/template'])",
        backName: /Kembali ke Import CSV$/,
        kind: "job Import",
      },
      {
        list: "/returns",
        selector: "main a[href^='/returns/']",
        backName: /Kembali ke Retur & Klaim$/,
        kind: "Retur",
      },
    ] as const) {
      await page.goto(flow.list, { waitUntil: "domcontentloaded" });
      const detailLink = page.locator(flow.selector).filter({ visible: true }).first();

      if (await detailLink.count() === 0) {
        testInfo.annotations.push({
          type: "fixture",
          description: `${flow.kind} tidak tersedia; tidak membuat mutation untuk smoke.`,
        });
        continue;
      }

      await detailLink.click();
      await page.reload({ waitUntil: "domcontentloaded" });
      await expect(page.getByRole("link", { name: flow.backName })).toBeVisible();
      await expectNoRootOverflow(page);
      await page.getByRole("link", { name: flow.backName }).click();
      await page.waitForURL((url) => url.pathname === flow.list);
    }
  },
);

test(
  "detail kontekstual mempertahankan list state saat reload dan kembali",
  async ({ page }, testInfo) => {
    await loginAsAdmin(page);

    const flows = [
      {
        list: "/products?q=SER",
        selector: "main a[href^='/products/']",
        detail: /^\/products\/[^/]+$/,
        backName: "Kembali ke Stok",
      },
      {
        list: "/ledger?page=1",
        selector: "main a[href^='/ledger/']",
        detail: /^\/ledger\/[^/]+$/,
        backName: "Kembali ke Riwayat Stok",
      },
      {
        list: "/stocktakes",
        selector: "main a[href^='/stocktakes/']:not([href='/stocktakes/new'])",
        detail: /^\/stocktakes\/[^/]+$/,
        backName: "Kembali ke Hitung Stok",
      },
      {
        list: "/marketplace?channel=SHOPEE",
        selector: "main a[href^='/marketplace/']",
        detail: /^\/marketplace\/[^/]+$/,
        backName: "Kembali ke daftar",
      },
    ] as const;

    for (const flow of flows) {
      await page.goto(flow.list, { waitUntil: "domcontentloaded" });
      const detailLink = page.locator(flow.selector).filter({ visible: true }).first();

      if (await detailLink.count() === 0) {
        testInfo.annotations.push({
          type: "fixture",
          description: `${flow.list} tidak memiliki detail fixture; flow dilewati tanpa mutation.`,
        });
        continue;
      }

      await expect(detailLink, flow.list).toBeVisible();
      await detailLink.click();
      await page.waitForURL((url) => flow.detail.test(url.pathname));

      await page.reload({ waitUntil: "domcontentloaded" });
      const backLink = page.getByRole("link", {
        name: new RegExp(`${flow.backName}$`),
      });
      await expect(backLink).toHaveAttribute("href", flow.list);
      await expectNoRootOverflow(page);
      await backLink.click();
      await page.waitForURL((url) => `${url.pathname}${url.search}` === flow.list);
    }

    await page.goto("/products?q=SER", { waitUntil: "domcontentloaded" });
    await page.locator("main a[href^='/products/']").filter({ visible: true }).first().click();
    await page.waitForURL((url) => /^\/products\/[^/]+$/.test(url.pathname));
    const productUrl = new URL(page.url());
    productUrl.searchParams.set("tab", "batches");
    await page.goto(productUrl.toString(), { waitUntil: "domcontentloaded" });
    const batchLink = page.locator("main a[href*='/batches/']").filter({ visible: true }).first();
    await expect(batchLink).toBeVisible();
    await batchLink.click();
    await page.waitForURL((url) => /\/products\/[^/]+\/batches\/[^/]+$/.test(url.pathname));
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(
      page.getByRole("link", { name: "Kembali ke Produk", exact: true }),
    ).toHaveAttribute("href", new RegExp("^/products/[^?]+\\?"));
    await expectNoRootOverflow(page);
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

    const sidebar = page.locator("aside").filter({
      has: page.locator("nav[aria-label='Navigasi utama']"),
    });
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
  "action Retur dari Beranda mempertahankan object context",
  async ({ page }) => {
    const expectedHref =
      process.env.PLAYWRIGHT_RETURN_NOTIFICATION_ROUTE;
    test.skip(
      !expectedHref,
      "Memerlukan action route dari fixture notification Retur aktif.",
    );

    const runtimeErrors: string[] = [];
    const serverFailures: string[] = [];

    page.on("console", (message) => {
      if (message.type() === "error") {
        runtimeErrors.push(message.text());
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

    const action = page
      .locator(`main a[href=${JSON.stringify(expectedHref)}]`)
      .first();
    await expect(action).toBeVisible();

    const href = await action.getAttribute("href");
    expect(href).toBeTruthy();

    const expected = new URL(href!, "http://internal.local");
    const returnId = expected.searchParams.get("returnId");
    const claimId = expected.searchParams.get("claimId");

    expect(returnId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );

    await action.click();
    await page.waitForURL((url) => {
      return (
        url.pathname === `/returns/${returnId}` &&
        (!claimId || url.searchParams.get("claimId") === claimId)
      );
    });

    if (claimId) {
      await expect(page.locator("#claim-detail")).toBeVisible();
      expect(new URL(page.url()).hash).toBe("#claim-detail");
    }

    const orderLink = page
      .locator("nav[aria-label='Navigasi utama']")
      .getByRole("link", { name: "Pesanan", exact: true })
      .filter({ visible: true });
    await expect(orderLink).toHaveAttribute("aria-current", "page");

    await page.reload({ waitUntil: "domcontentloaded" });
    expect(new URL(page.url()).pathname).toBe(`/returns/${returnId}`);
    if (claimId) {
      expect(new URL(page.url()).searchParams.get("claimId")).toBe(claimId);
      await expect(page.locator("#claim-detail")).toBeVisible();
    }

    const overflow = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      viewportWidth: document.documentElement.clientWidth,
    }));
    expect(overflow.scrollWidth).toBeLessThanOrEqual(
      overflow.viewportWidth + 1,
    );

    await page
      .getByRole("link", { name: "Kembali ke Retur & Klaim", exact: true })
      .click();
    await page.waitForURL((url) => url.pathname === "/returns");

    expect(runtimeErrors).toEqual([]);
    expect(serverFailures).toEqual([]);
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

test(
  "manual outbound menampilkan referensi Promo aktif dan mempertahankan referensi generic",
  async ({ page }) => {
    const pageErrors: string[] = [];
    const consoleErrors: string[] = [];
    const hydrationErrors: string[] = [];

    page.on("pageerror", (error) => pageErrors.push(error.message));
    page.on("console", (message) => {
      if (message.type() !== "error") return;
      consoleErrors.push(message.text());
      if (/hydration/i.test(message.text())) hydrationErrors.push(message.text());
    });

    await loginAsAdmin(page);

    const fixtureSuffix = Date.now().toString(36).toUpperCase();
    const activeFixtureCode = `E2E_ACTIVE_${fixtureSuffix}`;
    const inactiveFixtureCode = `E2E_INACTIVE_${fixtureSuffix}`;

    async function createPromoFixture(code: string, name: string) {
      await page.goto("/settings/promos", { waitUntil: "domcontentloaded" });
      const createPromo = page.locator("#promo-create-form");
      await createPromo.locator("summary").click();
      await createPromo.getByLabel("Kode Promo", { exact: true }).fill(code);
      await createPromo.getByLabel("Nama Promo", { exact: true }).fill(name);
      await createPromo.getByRole("button", { name: "Tambah Promo", exact: true }).click();
      await expect(page.getByText(code, { exact: true })).toBeVisible();
    }

    await createPromoFixture(activeFixtureCode, `E2E Active ${fixtureSuffix}`);
    await createPromoFixture(inactiveFixtureCode, `E2E Inactive ${fixtureSuffix}`);

    const inactiveRow = page.locator("div.group.grid").filter({ hasText: inactiveFixtureCode });
    await inactiveRow.locator("summary", { hasText: "Nonaktifkan" }).click();
    await inactiveRow.getByLabel("Alasan Penonaktifan", { exact: true }).fill("Fixture browser inactive");
    await inactiveRow.getByRole("checkbox").check();
    await inactiveRow.getByRole("button", { name: "Nonaktifkan", exact: true }).click();
    await expect(inactiveRow.getByText("Tidak Aktif", { exact: true })).toBeVisible();

    await page.goto("/settings/promos", { waitUntil: "domcontentloaded" });
    const promoRows = page.locator("div.group.grid");
    const activePromoCodes = await promoRows
      .filter({ has: page.getByText("Aktif", { exact: true }) })
      .locator("p.ui-code")
      .allTextContents();
    const inactivePromoCodes = await promoRows
      .filter({ has: page.getByText("Tidak Aktif", { exact: true }) })
      .locator("p.ui-code")
      .allTextContents();

    expect(activePromoCodes).toContain(activeFixtureCode);

    await page.goto("/manual-outbounds", { waitUntil: "domcontentloaded" });
    const reason = page.locator("#outbound-reason");
    const promoSelector = page.locator("#outbound-promo-selector");
    const genericReference = page.locator("#outbound-business-reference");

    await expect(reason).toHaveValue("OFFLINE_SALE");
    await expect(promoSelector).toHaveCount(0);
    await expect(genericReference).toHaveCount(0);

    await reason.selectOption("PROMO");
    await expect(promoSelector).toBeVisible();
    await expect(promoSelector).toHaveValue("");

    const selectablePromoCodes = await promoSelector.locator("option").evaluateAll(
      (options) => options.flatMap((option) => {
        const candidate = option as HTMLOptionElement;
        return !candidate.disabled && candidate.value ? [candidate.value] : [];
      }),
    );
    expect(selectablePromoCodes.sort()).toEqual([...activePromoCodes].sort());
    expect(selectablePromoCodes).not.toContain(inactiveFixtureCode);
    expect(selectablePromoCodes).not.toEqual(expect.arrayContaining(inactivePromoCodes));

    await promoSelector.selectOption(activePromoCodes[0]);
    await expect(promoSelector).toHaveValue(activePromoCodes[0]);

    await reason.selectOption("BONUS");
    await expect(promoSelector).toHaveCount(0);
    await expect(genericReference).toBeVisible();

    await reason.selectOption("SAMPLE");
    await expect(promoSelector).toHaveCount(0);
    await expect(genericReference).toBeVisible();

    await reason.selectOption("OFFLINE_SALE");
    await expect(promoSelector).toHaveCount(0);
    await expect(genericReference).toHaveCount(0);

    expect(pageErrors, `pageerror: ${pageErrors.join(" | ")}`).toEqual([]);
    expect(hydrationErrors, `hydration: ${hydrationErrors.join(" | ")}`).toEqual([]);
    expect(consoleErrors, `console.error: ${consoleErrors.join(" | ")}`).toEqual([]);
  },
);