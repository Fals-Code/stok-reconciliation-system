param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$BaseUrl = "http://127.0.0.1:3000",
  [string]$Email = "demo.admin@glowlab.invalid",
  [SecureString]$Password,
  [switch]$KeepServer,
  [switch]$SkipBrowserInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-AppReady {
  param([string]$Url)

  try {
    $response = Invoke-WebRequest `
      -Uri "$Url/login" `
      -UseBasicParsing `
      -TimeoutSec 3

    return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
  }
  catch {
    return $false
  }
}

function Stop-ProcessTree {
  param([System.Diagnostics.Process]$Process)

  if (-not $Process) {
    return
  }

  try {
    if (-not $Process.HasExited) {
      & taskkill.exe /PID $Process.Id /T /F *> $null
    }
  }
  catch {
    Write-Warning "Dev server process could not be stopped automatically."
  }
}

$requiredFiles = @(
  "package.json",
  ".env.local",
  "src\app\login\page.tsx",
  "src\app\reconciliation\page.tsx",
  "scripts\create-demo-admin.mjs"
)

foreach ($relativePath in $requiredFiles) {
  $fullPath = Join-Path $ProjectRoot $relativePath

  if (-not (Test-Path $fullPath)) {
    throw "Required file was not found: $fullPath"
  }
}

$branch = (git -C $ProjectRoot branch --show-current).Trim()
if ($branch -ne "agent/phase2-return-semantics") {
  throw "Expected branch 'agent/phase2-return-semantics', found '$branch'."
}

$npmCommand = (Get-Command npm.cmd -ErrorAction Stop).Source
$npxCommand = (Get-Command npx.cmd -ErrorAction Stop).Source

if (-not $Password) {
  $Password = Read-Host `
    "Enter the local Demo Admin password" `
    -AsSecureString
}

$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$plainPassword = $null
$devProcess = $null
$serverWasStarted = $false
$testFile = Join-Path $ProjectRoot "reconciliation-smoke.generated.spec.cjs"
$configFile = Join-Path $ProjectRoot "playwright.smoke.generated.config.cjs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactDirectory = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  "stok-reconciliation-smoke\$timestamp"
$serverOutLog = Join-Path $artifactDirectory "dev-server.stdout.log"
$serverErrLog = Join-Path $artifactDirectory "dev-server.stderr.log"

New-Item `
  -ItemType Directory `
  -Path $artifactDirectory `
  -Force | Out-Null

try {
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    $passwordPointer
  )

  Write-Step "Checking application server"

  if (-not (Test-AppReady -Url $BaseUrl)) {
    Write-Host "No server is responding at $BaseUrl. Starting npm run dev..."

    $devProcess = Start-Process `
      -FilePath $npmCommand `
      -ArgumentList @("run", "dev") `
      -WorkingDirectory $ProjectRoot `
      -RedirectStandardOutput $serverOutLog `
      -RedirectStandardError $serverErrLog `
      -PassThru

    $serverWasStarted = $true
    $deadline = (Get-Date).AddSeconds(90)

    while ((Get-Date) -lt $deadline) {
      if ($devProcess.HasExited) {
        $stdout = if (Test-Path $serverOutLog) {
          Get-Content $serverOutLog -Raw
        } else {
          ""
        }

        $stderr = if (Test-Path $serverErrLog) {
          Get-Content $serverErrLog -Raw
        } else {
          ""
        }

        throw @"
Dev server exited before becoming ready.

STDOUT:
$stdout

STDERR:
$stderr
"@
      }

      if (Test-AppReady -Url $BaseUrl) {
        break
      }

      Start-Sleep -Seconds 2
    }

    if (-not (Test-AppReady -Url $BaseUrl)) {
      throw "Dev server did not become ready within 90 seconds."
    }
  }
  else {
    Write-Host "Using the existing server at $BaseUrl."
  }

  Write-Step "Preparing Playwright"

  $playwrightPackage = Join-Path `
    $ProjectRoot `
    "node_modules\@playwright\test\package.json"

  if (-not (Test-Path $playwrightPackage)) {
    Write-Host "Installing @playwright/test temporarily without changing package.json..."

    Push-Location $ProjectRoot
    try {
      & $npmCommand install `
        --no-save `
        --package-lock=false `
        --ignore-scripts `
        "@playwright/test@latest"

      if ($LASTEXITCODE -ne 0) {
        throw "Temporary Playwright installation failed."
      }
    }
    finally {
      Pop-Location
    }
  }

  if (-not $SkipBrowserInstall) {
    Write-Host "Ensuring Chromium is installed..."

    Push-Location $ProjectRoot
    try {
      & $npxCommand playwright install chromium

      if ($LASTEXITCODE -ne 0) {
        throw "Chromium installation failed."
      }
    }
    finally {
      Pop-Location
    }
  }

  $testContent = @'
const fs = require("node:fs");
const path = require("node:path");
const { test, expect } = require("@playwright/test");

const email = process.env.SMOKE_ADMIN_EMAIL;
const password = process.env.SMOKE_ADMIN_PASSWORD;
const artifactDirectory = process.env.SMOKE_ARTIFACT_DIR;

if (!email || !password || !artifactDirectory) {
  throw new Error("Smoke test environment is incomplete.");
}

fs.mkdirSync(artifactDirectory, { recursive: true });

const checkCodes = [
  "LEDGER_BATCH_PROJECTION",
  "BATCH_PRODUCT_PROJECTION",
  "RESERVATION_CONSISTENCY",
  "MARKETPLACE_ALLOCATION_CONSISTENCY",
  "RETURN_RECEIPT_CONSISTENCY",
  "RETURN_INSPECTION_CONSISTENCY",
  "DUPLICATE_SOURCE_EFFECT",
  "IMPOSSIBLE_PROJECTION_STATE",
];

function detectMojibake(text) {
  const suspiciousCharacters = [
    String.fromCharCode(0x00c2),
    String.fromCharCode(0x00c3),
    String.fromCharCode(0x00e2),
    String.fromCharCode(0x252c),
    String.fromCharCode(0x2556),
    String.fromCharCode(0xfffd),
  ];

  return suspiciousCharacters.filter((character) => text.includes(character));
}

test("Admin reconciliation smoke flow", async ({ page }) => {
  const consoleErrors = [];
  const pageErrors = [];
  const mojibakeFindings = [];

  page.on("console", (message) => {
    const text = message.text();
    const isDevHmrNoise =
      text.includes("/_next/webpack-hmr") &&
      text.includes("WebSocket connection") &&
      text.includes("ERR_INVALID_HTTP_RESPONSE");

    if (message.type() === "error" && !isDevHmrNoise) {
      consoleErrors.push(text);
    }
  });

  page.on("pageerror", (error) => {
    pageErrors.push(error.message);
  });

  async function inspectPage(label) {
    const bodyText = await page.locator("body").innerText();
    const suspicious = detectMojibake(bodyText);

    if (suspicious.length > 0) {
      mojibakeFindings.push(
        `${label}: ${suspicious
          .map((character) => `U+${character.charCodeAt(0).toString(16).toUpperCase()}`)
          .join(", ")}`
      );
    }
  }

  await test.step("Unauthenticated access redirects to login", async () => {
    await page.goto("/reconciliation");
    await expect(page).toHaveURL(/\/login/);
    await expect(page.getByRole("heading", { name: "Masuk sebagai Admin." }))
      .toBeVisible();
  });

  await test.step("Admin can log in", async () => {
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Password").fill(password);
    await page.getByRole("button", { name: "Masuk ke dashboard" }).click();
    await page.waitForURL((url) => url.pathname === "/", { timeout: 30000 });
  });

  await test.step("Reconciliation page renders its main controls", async () => {
    await page.goto("/reconciliation");

    await expect(
      page.getByRole("heading", { name: /Pastikan catatan stok/ })
    ).toBeVisible();

    await expect(
      page.getByRole("button", { name: "Periksa konsistensi stok" })
    ).toBeVisible();

    const checkboxes = page.locator('input[name="checkCodes"]');
    await expect(checkboxes).toHaveCount(8);

    for (let index = 0; index < 8; index += 1) {
      await expect(checkboxes.nth(index)).toBeChecked();
    }

    const idempotencyKey = await page
      .locator('input[name="idempotencyKey"]')
      .inputValue();

    expect(idempotencyKey).toMatch(
      /^reconciliation:admin-ui:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    );

    await inspectPage("initial reconciliation page");

    await page.screenshot({
      path: path.join(artifactDirectory, "01-before-run.png"),
      fullPage: true,
    });
  });

  let latestRunText = "";

  await test.step("All eight checks can run successfully", async () => {
    await page.getByRole("button", { name: "Periksa konsistensi stok" }).click();

    await page.waitForURL(
      (url) =>
        url.pathname === "/reconciliation" &&
        url.searchParams.has("success"),
      { timeout: 90000 }
    );

    const latestRunCard = page
      .locator("article")
      .filter({ hasText: "Pemeriksaan terakhir" });

    await expect(latestRunCard).toBeVisible();
    await expect(latestRunCard).not.toContainText("Belum ada");

    latestRunText = (await latestRunCard.innerText()).trim();

    await expect(
      page.getByText("Belum ada reconciliation run.")
    ).toHaveCount(0);

    await expect(
      page.getByText("Belum ada run", { exact: true })
    ).toHaveCount(0);

    for (const checkCode of checkCodes) {
      expect(
        await page.getByText(checkCode, { exact: true }).count(),
        `Expected persisted result for ${checkCode}`
      ).toBeGreaterThanOrEqual(2);
    }

    await inspectPage("reconciliation result page");

    await page.screenshot({
      path: path.join(artifactDirectory, "02-after-run.png"),
      fullPage: true,
    });
  });

  await test.step("Run remains visible after refresh", async () => {
    await page.reload();

    const latestRunCard = page
      .locator("article")
      .filter({ hasText: "Pemeriksaan terakhir" });

    await expect(latestRunCard).toContainText(
      latestRunText
        .split(/\r?\n/)
        .filter(Boolean)
        .slice(1, 2)
        .join("")
    );

    await inspectPage("reconciliation page after refresh");
  });

  await test.step("Issue filters submit through the URL", async () => {
    await page.getByLabel("Status temuan").selectOption("OPEN");
    await page.getByLabel("Tingkat masalah").selectOption("HIGH");
    await page.getByRole("button", { name: "Terapkan filter" }).click();

    await page.waitForURL(
      (url) =>
        url.pathname === "/reconciliation" &&
        url.searchParams.get("status") === "OPEN" &&
        url.searchParams.get("severity") === "HIGH",
      { timeout: 30000 }
    );
  });

  await test.step("Reconciliation navigation works from all Admin pages", async () => {
    const destinations = ["/", "/marketplace", "/returns"];

    for (const pathname of destinations) {
      await page.goto("/reconciliation");

      const destinationLink = page
        .locator(
          `nav[aria-label="Navigasi utama"] a[href="${pathname}"]`
        )
        .first();

      await expect(destinationLink).toBeVisible();
      await destinationLink.click();

      await page.waitForURL(
        (url) => url.pathname === pathname,
        { timeout: 30000 }
      );

      const reconciliationLink = page
        .locator(
          'nav[aria-label="Navigasi utama"] a[href="/reconciliation"]'
        )
        .first();

      await expect(reconciliationLink).toBeVisible();
      await reconciliationLink.click();

      await page.waitForURL(
        (url) => url.pathname === "/reconciliation",
        { timeout: 30000 }
      );
    }
  });

  await page.screenshot({
    path: path.join(artifactDirectory, "03-final.png"),
    fullPage: true,
  });

  const failures = [];

  if (consoleErrors.length > 0) {
    failures.push(
      `Browser console errors:\n${consoleErrors
        .map((message) => `- ${message}`)
        .join("\n")}`
    );
  }

  if (pageErrors.length > 0) {
    failures.push(
      `Unhandled page errors:\n${pageErrors
        .map((message) => `- ${message}`)
        .join("\n")}`
    );
  }

  if (mojibakeFindings.length > 0) {
    failures.push(
      `Mojibake detected:\n${mojibakeFindings
        .map((message) => `- ${message}`)
        .join("\n")}`
    );
  }

  expect(failures, failures.join("\n\n")).toEqual([]);
});
'@

  $configContent = @'
const path = require("node:path");

module.exports = {
  testDir: ".",
  testMatch: "reconciliation-smoke.generated.spec.cjs",
  timeout: 120000,
  expect: {
    timeout: 15000,
  },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["line"]],
  outputDir: process.env.SMOKE_ARTIFACT_DIR,
  use: {
    baseURL: process.env.SMOKE_BASE_URL,
    headless: true,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
};
'@

  $ascii = New-Object System.Text.ASCIIEncoding
  [System.IO.File]::WriteAllText($testFile, $testContent, $ascii)
  [System.IO.File]::WriteAllText($configFile, $configContent, $ascii)

  $env:SMOKE_BASE_URL = $BaseUrl.TrimEnd("/")
  $env:SMOKE_ADMIN_EMAIL = $Email
  $env:SMOKE_ADMIN_PASSWORD = $plainPassword
  $env:SMOKE_ARTIFACT_DIR = $artifactDirectory

  Write-Step "Running reconciliation smoke test"

  Push-Location $ProjectRoot
  try {
    & $npxCommand playwright test `
      --config $configFile

    $testExitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }

  if ($testExitCode -ne 0) {
    throw "Reconciliation smoke test failed. Review artifacts: $artifactDirectory"
  }

  Write-Host ""
  Write-Host "SMOKE TEST: PASS" -ForegroundColor Green
  Write-Host "Artifacts: $artifactDirectory"
}
finally {
  if ($passwordPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
  }

  $env:SMOKE_ADMIN_PASSWORD = $null
  $env:SMOKE_ADMIN_EMAIL = $null
  $env:SMOKE_BASE_URL = $null
  $env:SMOKE_ARTIFACT_DIR = $null

  Remove-Variable plainPassword -ErrorAction SilentlyContinue
  Remove-Variable Password -ErrorAction SilentlyContinue

  Remove-Item $testFile -Force -ErrorAction SilentlyContinue
  Remove-Item $configFile -Force -ErrorAction SilentlyContinue

  if ($serverWasStarted -and -not $KeepServer) {
    Write-Step "Stopping the dev server started by this script"
    Stop-ProcessTree -Process $devProcess
  }
}
