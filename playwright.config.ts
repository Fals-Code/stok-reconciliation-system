import {
  defineConfig,
  devices,
} from "@playwright/test";

const isolatedPort = process.env.PLAYWRIGHT_ISOLATED_PORT;

const baseURL = (
  process.env.PLAYWRIGHT_BASE_URL ??
  "http://localhost:3000"
).replace(/\/+$/, "");

export default defineConfig({
  testDir: "./tests/e2e",
  outputDir: "test-results/playwright",
  fullyParallel: false,
  forbidOnly: true,
  workers: 1,
  retries: 0,
  timeout: 45_000,

  expect: {
    timeout: 7_500,
  },

  reporter: [
    ["line"],
    [
      "html",
      {
        open: "never",
        outputFolder: "playwright-report",
      },
    ],
  ],

  use: {
    baseURL,
    locale: "id-ID",
    timezoneId: "Asia/Jakarta",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },

  webServer: {
    command: isolatedPort ? `npm run dev -- --port ${isolatedPort}` : "npm run dev",
    url: `${baseURL}/login`,
    reuseExistingServer: !isolatedPort,
    timeout: 120_000,
    stdout: "pipe",
    stderr: "pipe",
  },

  projects: [
    {
      name: "desktop-chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: {
          width: 1440,
          height: 900,
        },
      },
    },
    {
      name: "mobile-chromium",
      use: {
        ...devices["Pixel 7"],
      },
    },
  ],
});