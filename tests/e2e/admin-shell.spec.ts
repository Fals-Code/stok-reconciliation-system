import {
  expect,
  test,
  type Locator,
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
    page.locator(
      '[data-app-topbar="admin"]',
    ),
  ).toBeVisible();
}

function getNotificationElements(page: Page) {
  const details = page.locator(
    'details[data-exclusive-popover="notification"]',
  );

  return {
    details,
    trigger: details.locator("summary").first(),
    panel: details.locator(
      "[data-notification-preview]",
    ),
  };
}

function getAccountElements(page: Page) {
  const details = page.locator(
    'details[data-exclusive-popover="account"]',
  );

  return {
    details,
    trigger: details.locator("summary").first(),
    panel: details.locator(
      "[data-account-popover]",
    ),
  };
}

async function expectInsideViewport(
  page: Page,
  locator: Locator,
) {
  const viewport = page.viewportSize();
  const box = await locator.boundingBox();

  if (!viewport || !box) {
    throw new Error(
      "Viewport atau bounding box tidak tersedia.",
    );
  }

  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(
    box.x + box.width,
  ).toBeLessThanOrEqual(viewport.width + 1);
  expect(
    box.y + box.height,
  ).toBeLessThanOrEqual(viewport.height + 1);
}

async function expectSpaciousPopover({
  page,
  panel,
  trigger,
}: {
  page: Page;
  panel: Locator;
  trigger: Locator;
}) {
  const triggerBox = await trigger.boundingBox();
  const panelBox = await panel.boundingBox();

  if (!triggerBox || !panelBox) {
    throw new Error(
      "Bounding box trigger atau popover tidak tersedia.",
    );
  }

  const triggerBottom =
    triggerBox.y + triggerBox.height;
  const gap = panelBox.y - triggerBottom;

  // mt-3 = sekitar 12 px, dengan toleransi rendering.
  expect(gap).toBeGreaterThanOrEqual(8);
  expect(gap).toBeLessThanOrEqual(20);

  const styles = await panel.evaluate(
    (element) => {
      const computed =
        window.getComputedStyle(element);

      return {
        overflowX: computed.overflowX,
        overflowY: computed.overflowY,
        bottomLeftRadius:
          Number.parseFloat(
            computed.borderBottomLeftRadius,
          ),
        bottomRightRadius:
          Number.parseFloat(
            computed.borderBottomRightRadius,
          ),
      };
    },
  );

  expect(styles.overflowX).toBe("hidden");
  expect(styles.overflowY).toBe("hidden");
  expect(styles.bottomLeftRadius).toBeGreaterThan(0);
  expect(styles.bottomRightRadius).toBeGreaterThan(0);

  await expectInsideViewport(page, panel);
}

async function moveThroughHoverBridge({
  page,
  panel,
  trigger,
}: {
  page: Page;
  panel: Locator;
  trigger: Locator;
}) {
  const triggerBox = await trigger.boundingBox();
  const panelBox = await panel.boundingBox();

  if (!triggerBox || !panelBox) {
    throw new Error(
      "Bounding box hover bridge tidak tersedia.",
    );
  }

  const triggerBottom =
    triggerBox.y + triggerBox.height;
  const gap = panelBox.y - triggerBottom;

  const triggerCenterX =
    triggerBox.x + triggerBox.width / 2;

  const bridgeX = Math.min(
    Math.max(
      triggerCenterX,
      panelBox.x + 8,
    ),
    panelBox.x + panelBox.width - 8,
  );

  await page.mouse.move(
    bridgeX,
    triggerBottom + gap / 2,
    {
      steps: 5,
    },
  );

  await expect(panel).toBeVisible();

  await page.mouse.move(
    bridgeX,
    panelBox.y + 8,
    {
      steps: 5,
    },
  );

  await expect(panel).toBeVisible();
}

test(
  "popover notifikasi memiliki jarak, clipping, dan hover bridge yang benar",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan hover khusus desktop.",
    );

    await loginAsAdmin(page);

    const {
      trigger,
      panel,
    } = getNotificationElements(page);

    await trigger.hover();
    await expect(panel).toBeVisible();

    await expect(panel).toHaveAttribute(
      "data-notification-preview-mode",
      "latest",
    );

    await expect(panel).toHaveAttribute(
      "data-popover-offset",
      "spacious",
    );

    await expect(panel).toHaveAttribute(
      "data-popover-clip",
      "rounded",
    );

    await expectSpaciousPopover({
      page,
      panel,
      trigger,
    });

    await moveThroughHoverBridge({
      page,
      panel,
      trigger,
    });

    const notificationRows = panel.locator(
      'a[href*="notificationId="]',
    );

    const emptyState = panel.getByText(
      "Belum ada notifikasi.",
      {
        exact: true,
      },
    );

    const hasNotificationRows =
      (await notificationRows.count()) > 0;

    const hasEmptyState =
      await emptyState
        .isVisible()
        .catch(() => false);

    expect(
      hasNotificationRows || hasEmptyState,
      "Panel harus berisi notifikasi terbaru atau empty state.",
    ).toBeTruthy();

    const footer = panel.getByRole("link", {
      name: "Lihat semua notifikasi",
      exact: true,
    });

    await expect(footer).toBeVisible();

    const backgroundBeforeHover =
      await footer.evaluate(
        (element) =>
          window.getComputedStyle(element)
            .backgroundColor,
      );

    await footer.hover();

    await expect
      .poll(
        () =>
          footer.evaluate(
            (element) =>
              window.getComputedStyle(element)
                .backgroundColor,
          ),
        {
          timeout: 1_500,
        },
      )
      .not.toBe(backgroundBeforeHover);

    const viewport = page.viewportSize();

    if (!viewport) {
      throw new Error("Viewport tidak tersedia.");
    }

    await page.mouse.move(
      8,
      viewport.height - 8,
    );

    await expect(panel).toBeHidden();
  },
);

test(
  "popover notifikasi dan akun eksklusif serta dapat ditutup dengan Escape",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan hover dan keyboard khusus desktop.",
    );

    await loginAsAdmin(page);

    const notification =
      getNotificationElements(page);
    const account = getAccountElements(page);

    await notification.trigger.hover();
    await expect(
      notification.panel,
    ).toBeVisible();

    await account.trigger.hover();
    await expect(account.panel).toBeVisible();
    await expect(
      notification.details,
    ).not.toHaveAttribute("open", "");

    await notification.trigger.hover();
    await expect(
      notification.panel,
    ).toBeVisible();
    await expect(
      account.details,
    ).not.toHaveAttribute("open", "");

    const viewport = page.viewportSize();

    if (!viewport) {
      throw new Error("Viewport tidak tersedia.");
    }

    await page.mouse.move(
      8,
      viewport.height - 8,
    );

    await account.trigger.focus();
    await expect(account.trigger).toBeFocused();

    await page.keyboard.press("Enter");

    await expect(account.panel).toBeVisible();
    await expect(account.details).toHaveAttribute(
      "open",
      "",
    );

    await page.keyboard.press("Escape");

    await expect(
      account.details,
    ).not.toHaveAttribute("open", "");

    await expect(account.panel).toBeHidden();
  },
);

test(
  "skip link, keyboard popover, dan preferensi sidebar bekerja setelah reload",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan desktop khusus keyboard dan sidebar.",
    );

    await loginAsAdmin(page);

    // Redirect login dapat mempertahankan fokus tombol
    // submit. Fresh navigation menguji urutan Tab pada
    // dokumen terautentikasi yang baru dimuat.
    await page.goto("/", {
      waitUntil: "domcontentloaded",
    });

    await expect(
      page.locator(
        '[data-app-topbar="admin"]',
      ),
    ).toBeVisible();

    await page.keyboard.press("Tab");

    const skipLink = page.getByRole("link", {
      name: /lewati.*konten/i,
    });

    await expect(skipLink).toBeFocused();

    await page.keyboard.press("Enter");

    await expect(
      page.locator("#main-content"),
    ).toBeFocused();

    const notification =
      getNotificationElements(page);

    await notification.trigger.focus();
    await expect(
      notification.trigger,
    ).toBeFocused();

    await page.keyboard.press("Enter");

    await expect(
      notification.panel,
    ).toBeVisible();

    await expect(
      notification.details,
    ).toHaveAttribute("open", "");

    await page.keyboard.press("Tab");

    const focusMovedInside =
      await notification.details.evaluate(
        (details) => {
          const active =
            document.activeElement;
          const summary =
            details.querySelector("summary");

          return Boolean(
            active &&
              active !== summary &&
              details.contains(active),
          );
        },
      );

    expect(
      focusMovedInside,
      "Tab harus dapat masuk ke isi popover.",
    ).toBeTruthy();

    await page.keyboard.press("Escape");

    const sidebarToggle = page
      .locator(
        [
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="sidebar" i]',
          ',',
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="ciutkan" i]',
          ',',
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="perluas" i]',
        ].join(" "),
      )
      .first();

    await expect(sidebarToggle).toBeVisible();

    const initialLabel =
      await sidebarToggle.getAttribute(
        "aria-label",
      );

    expect(initialLabel).toBeTruthy();

    await sidebarToggle.click();

    const changedLabel =
      await sidebarToggle.getAttribute(
        "aria-label",
      );

    expect(changedLabel).toBeTruthy();
    expect(changedLabel).not.toBe(initialLabel);

    await page.reload({
      waitUntil: "domcontentloaded",
    });

    const persistedToggle = page
      .locator(
        [
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="sidebar" i]',
          ',',
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="ciutkan" i]',
          ',',
          '[data-app-topbar="admin"]',
          'button:visible[aria-label*="perluas" i]',
        ].join(" "),
      )
      .first();

    await expect(persistedToggle).toHaveAttribute(
      "aria-label",
      changedLabel ?? "",
    );
  },
);

test(
  "shell desktop bebas error browser, hydration, dan request penting yang gagal",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Pemeriksaan runtime dijalankan sekali pada desktop.",
    );

    const runtimeIssues: string[] = [];

    page.on("console", (message) => {
      if (message.type() === "error") {
        runtimeIssues.push(
          `console: ${message.text()}`,
        );
      }
    });

    page.on("pageerror", (error) => {
      runtimeIssues.push(
        `pageerror: ${error.message}`,
      );
    });

    page.on("requestfailed", (request) => {
      const importantTypes = new Set([
        "document",
        "script",
        "stylesheet",
        "fetch",
        "xhr",
      ]);

      if (
        !importantTypes.has(
          request.resourceType(),
        )
      ) {
        return;
      }

      const failure =
        request.failure()?.errorText ??
        "unknown failure";

      if (
        /ERR_ABORTED|NS_BINDING_ABORTED/i.test(
          failure,
        )
      ) {
        return;
      }

      runtimeIssues.push(
        [
          "requestfailed:",
          request.method(),
          request.url(),
          failure,
        ].join(" "),
      );
    });

    await loginAsAdmin(page);

    const notification =
      getNotificationElements(page);
    const account = getAccountElements(page);

    await notification.trigger.hover();
    await expect(
      notification.panel,
    ).toBeVisible();

    await account.trigger.hover();
    await expect(account.panel).toBeVisible();

    await page.reload({
      waitUntil: "domcontentloaded",
    });

    await page.waitForTimeout(750);

    expect(
      runtimeIssues,
      runtimeIssues.join("\n"),
    ).toEqual([]);
  },
);

test(
  "drawer mobile dan fallback tap popover bekerja tanpa keluar viewport",
  async ({ page, isMobile }) => {
    test.skip(
      !Boolean(isMobile),
      "Pemeriksaan khusus mobile.",
    );

    await loginAsAdmin(page);

    const openButton = page.getByRole(
      "button",
      {
        name: "Buka navigasi",
        exact: true,
      },
    );

    await expect(openButton).toBeVisible();
    await expect(openButton).toHaveAttribute(
      "aria-expanded",
      "false",
    );

    await openButton.tap();

    const drawer = page.locator(
      "#mobile-navigation",
    );

    const modal = page
      .locator('[aria-modal="true"]')
      .first();

    await expect(modal).toBeVisible();
    await expect(drawer).toBeVisible();
    await expect(openButton).toHaveAttribute(
      "aria-expanded",
      "true",
    );

    await expect
      .poll(() =>
        page.evaluate(
          () =>
            window.getComputedStyle(
              document.body,
            ).overflow,
        ),
      )
      .toBe("hidden");

    const closeButton = modal.getByRole(
      "button",
      {
        name: "Tutup menu",
        exact: true,
      },
    );

    await expect(closeButton).toBeFocused();

    await page.keyboard.press("Shift+Tab");

    const focusStillInside =
      await modal.evaluate(
        (element) =>
          element.contains(
            document.activeElement,
          ),
      );

    expect(
      focusStillInside,
      "Focus harus tetap berada di drawer.",
    ).toBeTruthy();

    await page.keyboard.press("Escape");

    await expect(drawer).toBeHidden();
    await expect(openButton).toBeFocused();
    await expect(openButton).toHaveAttribute(
      "aria-expanded",
      "false",
    );

    const notification =
      getNotificationElements(page);
    const account = getAccountElements(page);

    await notification.trigger.tap();

    await expect(
      notification.details,
    ).toHaveAttribute("open", "");

    await expect(
      notification.panel,
    ).toBeVisible();

    await expectInsideViewport(
      page,
      notification.panel,
    );

    await account.trigger.tap();

    await expect(
      account.details,
    ).toHaveAttribute("open", "");

    await expect(account.panel).toBeVisible();
    await expect(
      notification.panel,
    ).toBeHidden();

    await expectInsideViewport(
      page,
      account.panel,
    );

    await expect(
      account.panel.getByRole("button", {
        name: "Keluar dari akun",
        exact: true,
      }),
    ).toBeVisible();

    const noHorizontalOverflow =
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth + 1,
      );

    expect(
      noHorizontalOverflow,
      "Halaman mobile tidak boleh memiliki overflow horizontal.",
    ).toBeTruthy();
  },
);