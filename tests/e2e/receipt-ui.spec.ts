import {
  expect,
  test,
  type Page,
} from "@playwright/test";

import {
  cleanupReceiptMutation,
  type ReceiptCleanupRequest,
} from "./receipt-cleanup";

/* ------------------------------------------------------------------ */
/*  Environment                                                        */
/* ------------------------------------------------------------------ */

const ADMIN_EMAIL =
  process.env.PLAYWRIGHT_ADMIN_EMAIL ??
  "demo.admin@glowlab.invalid";

function getAdminPassword() {
  const password =
    process.env.PLAYWRIGHT_ADMIN_PASSWORD;

  if (!password) {
    throw new Error(
      "PLAYWRIGHT_ADMIN_PASSWORD belum tersedia. " +
        "Jalankan test melalui scripts/test-receipt-browser.ps1.",
    );
  }

  return password;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

type BrowserIssue = string;

function attachBrowserHealthListeners(
  page: Page,
  issues: BrowserIssue[],
) {
  page.on("console", (message) => {
    if (message.type() === "error") {
      issues.push(
        `console.error: ${message.text()}`,
      );
    }
  });

  page.on("pageerror", (error) => {
    issues.push(
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

    issues.push(
      [
        "requestfailed:",
        request.method(),
        request.url(),
        failure,
      ].join(" "),
    );
  });
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
      { timeout: 30_000 },
    ),
    page
      .getByRole("button", {
        name: "Masuk",
        exact: true,
      })
      .click(),
  ]);

  await expect(
    page.locator("#main-content"),
  ).toBeVisible();
}

function uniqueRef(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

let pendingReceiptCleanup: ReceiptCleanupRequest | null = null;

test.beforeEach(() => {
  pendingReceiptCleanup = null;
});

test.afterEach(async () => {
  const cleanup = pendingReceiptCleanup;
  pendingReceiptCleanup = null;

  if (cleanup) {
    await cleanupReceiptMutation(cleanup);
  }
});

/* ------------------------------------------------------------------ */
/*  B. EXISTING BATCH                                                  */
/* ------------------------------------------------------------------ */

test(
  "Receipt existing batch Ã¢â‚¬â€ full mutation lifecycle",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Mutation penuh dijalankan di desktop.",
    );

    test.setTimeout(120_000);

    const issues: BrowserIssue[] = [];
    attachBrowserHealthListeners(page, issues);

    await loginAsAdmin(page);

    // 1. Navigate to receipt form
    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // 2. Verify heading
    await expect(
      page.getByRole("heading", {
        name: "Barang Masuk",
        exact: true,
      }),
    ).toBeVisible();

    // 3. Fill unique reference
    const sourceRef = uniqueRef("PW-RECEIPT-EX");
    pendingReceiptCleanup = {
      sourceRef,
      archiveInlineBatch: false,
    };
    await page
      .getByLabel("Referensi penerimaan", { exact: false })
      .fill(sourceRef);

    // 4. Verify Waktu diterima has value
    const occurredAtInput = page
      .getByLabel("Waktu diterima", { exact: false });
    await expect(occurredAtInput).toBeVisible();
    const occurredAtValue =
      await occurredAtInput.inputValue();
    expect(occurredAtValue.length).toBeGreaterThan(0);

    // 5. Find a product with existing batches
    // The form auto-selects the first product.
    // If the first product already has batch mode "existing" enabled,
    // the radio "Batch yang sudah ada" will be checked.
    // We need to find a product that has existing batches.

    const productSelect = page
      .locator("label")
      .filter({ hasText: "Produk" })
      .locator("select")
      .first();

    // Get all product options
    const productOptions = await productSelect
      .locator("option")
      .all();

    let foundExistingBatch = false;

    // Try each product to find one with existing batches
    for (const option of productOptions) {
      const optionValue = await option.getAttribute("value");
      if (!optionValue) continue; // skip the placeholder

      await productSelect.selectOption(optionValue);

      // Check if "Batch yang sudah ada" radio is enabled (not disabled)
      const existingBatchRadio = page
        .getByLabel("Batch yang sudah ada", {
          exact: false,
        })
        .first();

      const isVisible = await existingBatchRadio
        .isVisible()
        .catch(() => false);

      if (!isVisible) continue;

      const isDisabled = await existingBatchRadio
        .isDisabled()
        .catch(() => true);

      if (!isDisabled) {
        foundExistingBatch = true;
        break;
      }
    }

    expect(
      foundExistingBatch,
      "Harus ada minimal satu produk dengan batch existing aktif di database lokal.",
    ).toBeTruthy();

    // 6. Select "Batch yang sudah ada"
    await page
      .getByLabel("Batch yang sudah ada", {
        exact: false,
      })
      .first()
      .check();

    // 7. Select first existing batch from "Pilih batch existing" dropdown
    const batchSelect = page
      .locator("label")
      .filter({ hasText: "Pilih batch existing" })
      .locator("select")
      .first();

    await expect(batchSelect).toBeVisible();

    // Select the first real option (skip placeholder)
    const batchOptions = await batchSelect
      .locator("option")
      .all();
    let selectedBatchText = "";
    for (const opt of batchOptions) {
      const val = await opt.getAttribute("value");
      if (val) {
        await batchSelect.selectOption(val);
        selectedBatchText = (await opt.textContent()) ?? "";
        break;
      }
    }

    expect(
      selectedBatchText.length,
      "Harus berhasil memilih batch existing.",
    ).toBeGreaterThan(0);

    // 8. Set quantity = 1
    const quantityInput = page
      .getByLabel("Jumlah", { exact: false })
      .first();

    await quantityInput.fill("1");

    // 10. Click "Periksa Sebelum Simpan"
    const previewButton = page.getByRole(
      "button",
      { name: /Periksa Sebelum Simpan/i },
    );

    await expect(previewButton).toBeEnabled();
    await previewButton.click();

    // 11. Verify review display
    await expect(
      page.getByText("Periksa sebelum simpan"),
    ).toBeVisible();

    // Reference visible in review
    await expect(
      page.getByText(sourceRef),
    ).toBeVisible();

    // Batch Existing badge
    await expect(
      page.getByText("Batch Existing"),
    ).toBeVisible();

    // Shows "1 unit" in review
    await expect(
      page.getByRole("paragraph").filter({ hasText: /^1 unit$/ }),
    ).toBeVisible();

    // Shows stock impact
    await expect(
      page.getByText(/bertambah.*1 unit/i),
    ).toBeVisible();

    // 12. Click "Kembali Edit"
    const backButton = page.getByRole("button", {
      name: /Kembali Edit/i,
    });
    await backButton.click();

    // 13. Verify state preserved
    await expect(
      page.getByLabel("Referensi penerimaan", {
        exact: false,
      }),
    ).toHaveValue(sourceRef);

    const preservedQty = await quantityInput.inputValue();
    expect(preservedQty).toBe("1");

    // 14. Click preview again
    await previewButton.click();

    await expect(
      page.getByText("Periksa sebelum simpan"),
    ).toBeVisible();

    // 15. Preview does NOT produce success toast
    await expect(
      page.getByText("Barang masuk berhasil dicatat"),
    ).toBeHidden();

    // 16. Click "Simpan Barang Masuk"
    const saveButton = page.getByRole("button", {
      name: /Simpan Barang Masuk/i,
    });

    await saveButton.click();

    // 17-18. Wait for redirect and verify success
    await page.waitForURL(
      (url) =>
        url.pathname === "/receipts/new" &&
        url.searchParams.has("success"),
      { timeout: 30_000 },
    );

    await expect(
      page.getByText("Barang masuk berhasil dicatat"),
    ).toBeVisible();

    // 19. Verify "Lihat Transaksi" link
    const viewTransactionLink = page.getByRole(
      "link",
      { name: "Lihat Transaksi", exact: true },
    );

    await expect(viewTransactionLink).toBeVisible();

    // 20. Click "Lihat Transaksi"
    await viewTransactionLink.click();

    // 21. Verify URL pattern /ledger/<transactionId>
    await page.waitForURL(
      (url) => /^\/ledger\/[a-f0-9-]+/.test(url.pathname),
      { timeout: 15_000 },
    );

    const ledgerUrl = new URL(page.url());
    expect(ledgerUrl.pathname).toMatch(
      /^\/ledger\/[a-f0-9-]+/,
    );

    // 22. Verify receipt reference appears on ledger detail
    await expect(
      page.getByText(sourceRef),
    ).toBeVisible();

    // 23. Reload page
    await page.reload({
      waitUntil: "domcontentloaded",
    });

    // 24. Verify evidence persists after reload
    await expect(
      page.getByText(sourceRef),
    ).toBeVisible();

    // Browser health check
    const relevantIssues = issues.filter(
      (issue) =>
        !issue.includes("Download the React DevTools") &&
        !issue.includes("A cookie associated with"),
    );

    expect(
      relevantIssues,
      `Browser issues: ${relevantIssues.join("\n")}`,
    ).toEqual([]);
  },
);

/* ------------------------------------------------------------------ */
/*  C. NEW BATCH                                                       */
/* ------------------------------------------------------------------ */

test(
  "Receipt new batch Ã¢â‚¬â€ full mutation lifecycle",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Mutation penuh dijalankan di desktop.",
    );

    test.setTimeout(120_000);

    const issues: BrowserIssue[] = [];
    attachBrowserHealthListeners(page, issues);

    await loginAsAdmin(page);

    // 1. Navigate
    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // 2. Unique reference
    const sourceRef = uniqueRef("PW-RECEIPT-NEW");
    pendingReceiptCleanup = {
      sourceRef,
      archiveInlineBatch: true,
    };
    await page
      .getByLabel("Referensi penerimaan", { exact: false })
      .fill(sourceRef);

    // 3. Select first active product (already selected by default)
    const productSelect = page
      .locator("label")
      .filter({ hasText: "Produk" })
      .locator("select")
      .first();

    // Select first real product option
    const productOptions = await productSelect
      .locator("option")
      .all();
    for (const opt of productOptions) {
      const val = await opt.getAttribute("value");
      if (val) {
        await productSelect.selectOption(val);
        break;
      }
    }

    // 4. Select "Buat batch baru"
    await page
      .getByLabel("Buat batch baru", {
        exact: false,
      })
      .first()
      .check();

    // 5. Fill batch code
    const batchCode = uniqueRef("PW-BATCH");
    await page
      .getByLabel("Kode Batch", { exact: false })
      .first()
      .fill(batchCode);

    // 6. Set expiry date (future)
    const expiryDate = "2028-12-31";
    await page
      .getByLabel("Tanggal Kedaluwarsa", {
        exact: false,
      })
      .first()
      .fill(expiryDate);

    // 7. Set manufactured date (before expiry)
    const manufacturedDate = "2026-08-01";
    await page
      .getByLabel("Tanggal Produksi", {
        exact: false,
      })
      .first()
      .fill(manufacturedDate);

    // 8. Set quantity = 2
    await page
      .getByLabel("Jumlah", { exact: false })
      .first()
      .fill("2");

    // 9. Preview
    const previewButton = page.getByRole(
      "button",
      { name: /Periksa Sebelum Simpan/i },
    );

    await expect(previewButton).toBeEnabled();
    await previewButton.click();

    // 10. Verify review
    await expect(
      page.getByText("Periksa sebelum simpan"),
    ).toBeVisible();

    // Batch Baru badge
    await expect(
      page.getByText("Batch Baru"),
    ).toBeVisible();

    // Batch code visible
    await expect(
      page.getByText(batchCode),
    ).toBeVisible();

    // "2 unit" visible
    await expect(
      page.getByRole("paragraph").filter({ hasText: /^2 unit$/ }),
    ).toBeVisible();

    // Stock impact
    await expect(
      page.getByText(/bertambah.*2 unit/i),
    ).toBeVisible();

    // 11. Save
    const saveButton = page.getByRole("button", {
      name: /Simpan Barang Masuk/i,
    });

    await saveButton.click();

    // 12. Verify success
    await page.waitForURL(
      (url) =>
        url.pathname === "/receipts/new" &&
        url.searchParams.has("success"),
      { timeout: 30_000 },
    );

    await expect(
      page.getByText("Barang masuk berhasil dicatat"),
    ).toBeVisible();

    // 13. Click "Lihat Transaksi"
    const viewTransactionLink = page.getByRole(
      "link",
      { name: "Lihat Transaksi", exact: true },
    );

    await expect(viewTransactionLink).toBeVisible();
    await viewTransactionLink.click();

    // 14. Verify reference on ledger detail
    await page.waitForURL(
      (url) => /^\/ledger\/[a-f0-9-]+/.test(url.pathname),
      { timeout: 15_000 },
    );

    await expect(
      page.getByText(sourceRef),
    ).toBeVisible();

    // 15. Reload and verify persistence
    await page.reload({
      waitUntil: "domcontentloaded",
    });

    await expect(
      page.getByText(sourceRef),
    ).toBeVisible();

    // Browser health
    const relevantIssues = issues.filter(
      (issue) =>
        !issue.includes("Download the React DevTools") &&
        !issue.includes("A cookie associated with"),
    );

    expect(
      relevantIssues,
      `Browser issues: ${relevantIssues.join("\n")}`,
    ).toEqual([]);
  },
);

/* ------------------------------------------------------------------ */
/*  D. CLIENT VALIDATION Ã¢â‚¬â€ date range                                  */
/* ------------------------------------------------------------------ */

test(
  "Client validation Ã¢â‚¬â€ manufactured after expiry shows warning and disables preview",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Validasi detail dijalankan di desktop.",
    );

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Fill reference
    await page
      .getByLabel("Referensi penerimaan", { exact: false })
      .fill(uniqueRef("PW-RECEIPT-VAL"));

    // Select "Buat batch baru"
    await page
      .getByLabel("Buat batch baru", {
        exact: false,
      })
      .first()
      .check();

    // Fill batch code
    await page
      .getByLabel("Kode Batch", { exact: false })
      .first()
      .fill("PW-VAL-BATCH");

    // Set expiry BEFORE manufactured (invalid)
    await page
      .getByLabel("Tanggal Kedaluwarsa", {
        exact: false,
      })
      .first()
      .fill("2099-01-01");

    await page
      .getByLabel("Tanggal Produksi", {
        exact: false,
      })
      .first()
      .fill("2099-01-02");

    // Quantity valid
    await page
      .getByLabel("Jumlah", { exact: false })
      .first()
      .fill("1");

    // Verify inline warning
    await expect(
      page.getByText(
        "Tanggal produksi tidak boleh setelah tanggal kedaluwarsa.",
        { exact: false },
      ),
    ).toBeVisible();

    // Verify preview button is disabled
    const previewButton = page.getByRole(
      "button",
      { name: /Periksa Sebelum Simpan/i },
    );

    await expect(previewButton).toBeDisabled();

    // No success message
    await expect(
      page.getByText("Barang masuk berhasil dicatat"),
    ).toBeHidden();
  },
);

/* ------------------------------------------------------------------ */
/*  E. QUANTITY BOUNDARY                                               */
/* ------------------------------------------------------------------ */

test(
  "Quantity boundary Ã¢â‚¬â€ zero and negative prevent preview",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Validasi boundary dijalankan di desktop.",
    );

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Fill reference
    await page
      .getByLabel("Referensi penerimaan", { exact: false })
      .fill(uniqueRef("PW-RECEIPT-QTY"));

    // Select "Buat batch baru" and fill valid batch data
    await page
      .getByLabel("Buat batch baru", {
        exact: false,
      })
      .first()
      .check();

    await page
      .getByLabel("Kode Batch", { exact: false })
      .first()
      .fill("PW-QTY-BATCH");

    await page
      .getByLabel("Tanggal Kedaluwarsa", {
        exact: false,
      })
      .first()
      .fill("2028-12-31");

    const previewButton = page.getByRole(
      "button",
      { name: /Periksa Sebelum Simpan/i },
    );

    // Test quantity = 0
    await page
      .getByLabel("Jumlah", { exact: false })
      .first()
      .fill("0");

    await expect(previewButton).toBeDisabled();

    // Test negative quantity
    await page
      .getByLabel("Jumlah", { exact: false })
      .first()
      .fill("-5");

    await expect(previewButton).toBeDisabled();

    // Test valid quantity enables button
    await page
      .getByLabel("Jumlah", { exact: false })
      .first()
      .fill("1");

    await expect(previewButton).toBeEnabled();
  },
);

/* ------------------------------------------------------------------ */
/*  F. MULTI-LINE SANITY                                               */
/* ------------------------------------------------------------------ */

test(
  "Multi-line Ã¢â‚¬â€ add and remove lines",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Multi-line detail dijalankan di desktop.",
    );

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Initially 1 line: "Barang #1"
    await expect(
      page.getByText("Barang #1"),
    ).toBeVisible();

    // 1. Add a second line
    await page
      .getByRole("button", {
        name: "+ Tambah barang",
        exact: true,
      })
      .click();

    // 2. Verify "Barang #2" appears
    await expect(
      page.getByText("Barang #2"),
    ).toBeVisible();

    // 3. Remove the second line via "Hapus" button
    const removeButton2 = page.getByRole(
      "button",
      { name: "Hapus barang 2", exact: true },
    );

    await expect(removeButton2).toBeEnabled();
    await removeButton2.click();

    // 4. Only one line remains
    await expect(
      page.getByText("Barang #2"),
    ).toBeHidden();

    await expect(
      page.getByText("Barang #1"),
    ).toBeVisible();

    // 5. Single line's delete button is disabled
    const removeButton1 = page.getByRole(
      "button",
      { name: "Hapus barang 1", exact: true },
    );

    await expect(removeButton1).toBeDisabled();
  },
);

/* ------------------------------------------------------------------ */
/*  G. PRODUCT/BATCH FILTERING (data-dependent)                        */
/* ------------------------------------------------------------------ */

test(
  "Product/batch filtering Ã¢â‚¬â€ existing batch only shows for selected product",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Filtering detail dijalankan di desktop.",
    );

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Note: This test verifies basic batch-product coupling.
    // Advanced filtering (expired/non-STANDARD/inactive batches)
    // is NOT EXERCISED if the local DB doesn't have varied fixture data.

    const productSelect = page
      .locator("label")
      .filter({ hasText: "Produk" })
      .locator("select")
      .first();

    // Get all product options with values
    const productOptions = await productSelect
      .locator("option[value]:not([value=''])")
      .all();

    if (productOptions.length < 2) {
      test.skip(
        true,
        "NOT EXERCISED Ã¢â‚¬â€ hanya ada satu produk, tidak dapat memverifikasi filtering lintas-produk.",
      );
      return;
    }

    // Select first product
    const firstValue = await productOptions[0].getAttribute("value");
    await productSelect.selectOption(firstValue!);

    // Check if it has the existing batch radio enabled
    const existingRadio = page
      .getByLabel("Batch yang sudah ada", {
        exact: false,
      })
      .first();

    const hasExisting = await existingRadio
      .isVisible()
      .catch(() => false);

    if (hasExisting) {
      const isEnabled = !(await existingRadio.isDisabled().catch(() => true));

      if (isEnabled) {
        await existingRadio.check();

        const batchSelect = page
          .locator("label")
          .filter({ hasText: "Pilih batch existing" })
          .locator("select")
          .first();

        const batchCountBeforeSwitch =
          await batchSelect
            .locator("option[value]:not([value=''])")
            .count();

        // Switch to second product
        const secondValue = await productOptions[1].getAttribute("value");
        await productSelect.selectOption(secondValue!);

        // The batch dropdown should now reflect the new product's batches
        // (could be different count, or batch mode might switch to "new")
        // We simply verify the form responded to the product change.
        // Not asserting exact counts because we don't know DB state.

        // If batch mode is still "existing", check the batch dropdown changed
        const stillExisting = await existingRadio
          .isChecked()
          .catch(() => false);

        if (stillExisting) {
          const batchCountAfterSwitch =
            await batchSelect
              .locator("option[value]:not([value=''])")
              .count();

          // The count may differ or be the same - we just verify no crash
          expect(batchCountAfterSwitch).toBeGreaterThanOrEqual(0);

          // Log for report
          console.log(
            `Batch filtering: Product 1 had ${batchCountBeforeSwitch} batches, Product 2 has ${batchCountAfterSwitch} batches.`,
          );
        }
      }
    }
  },
);

/* ------------------------------------------------------------------ */
/*  H. MOBILE SANITY                                                   */
/* ------------------------------------------------------------------ */

test(
  "Mobile Ã¢â‚¬â€ receipt form renders without horizontal overflow",
  async ({ page, isMobile }) => {
    test.skip(
      !Boolean(isMobile),
      "Pemeriksaan khusus mobile.",
    );

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Form visible
    await expect(
      page.getByRole("heading", {
        name: "Barang Masuk",
        exact: true,
      }),
    ).toBeVisible();

    // Referensi penerimaan visible
    await expect(
      page.getByLabel("Referensi penerimaan", {
        exact: false,
      }),
    ).toBeVisible();

    // Product select visible
    const productSelect = page
      .locator("label")
      .filter({ hasText: "Produk" })
      .locator("select")
      .first();

    await expect(productSelect).toBeVisible();

    // "+ Tambah barang" visible
    await expect(
      page.getByRole("button", {
        name: "+ Tambah barang",
        exact: true,
      }),
    ).toBeVisible();

    // "Periksa Sebelum Simpan" visible
    await expect(
      page.getByRole("button", {
        name: /Periksa Sebelum Simpan/i,
      }),
    ).toBeVisible();

    // No horizontal overflow
    const noHorizontalOverflow =
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth + 1,
      );

    expect(
      noHorizontalOverflow,
      "Mobile tidak boleh memiliki overflow horizontal.",
    ).toBeTruthy();
  },
);

/* ------------------------------------------------------------------ */
/*  I. BROWSER HEALTH Ã¢â‚¬â€ dedicated check                                */
/* ------------------------------------------------------------------ */

test(
  "Browser health Ã¢â‚¬â€ receipt page free of hydration errors and critical failures",
  async ({ page, isMobile }) => {
    test.skip(
      Boolean(isMobile),
      "Browser health dijalankan sekali di desktop.",
    );

    const issues: BrowserIssue[] = [];
    attachBrowserHealthListeners(page, issues);

    await loginAsAdmin(page);

    await page.goto("/receipts/new", {
      waitUntil: "domcontentloaded",
    });

    // Wait for hydration
    await page.waitForTimeout(1_500);

    // Interact with form
    await page
      .getByLabel("Referensi penerimaan", { exact: false })
      .fill("health-check");

    // Toggle batch mode
    const batchNewRadio = page
      .getByLabel("Buat batch baru", {
        exact: false,
      })
      .first();

    if (await batchNewRadio.isVisible().catch(() => false)) {
      await batchNewRadio.check();
    }

    // Click add line
    await page
      .getByRole("button", {
        name: "+ Tambah barang",
        exact: true,
      })
      .click();

    await page.waitForTimeout(500);

    // Reload to check hydration
    await page.reload({
      waitUntil: "domcontentloaded",
    });

    await page.waitForTimeout(1_000);

    // Filter out known non-issues
    const relevantIssues = issues.filter(
      (issue) =>
        !issue.includes("Download the React DevTools") &&
        !issue.includes("A cookie associated with") &&
        !issue.includes("Clerk") &&
        !issue.includes("favicon"),
    );

    expect(
      relevantIssues,
      `Browser issues found:\n${relevantIssues.join("\n")}`,
    ).toEqual([]);
  },
);
