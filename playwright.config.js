const { defineConfig } = require("@playwright/test");

const PORT = Number(process.env.PORT || 3210);

module.exports = defineConfig({
  testDir: "./tests",
  timeout: 120_000,
  fullyParallel: true,
  reporter: [["list"]],
  workers: Number(process.env.WORKERS || 8),
  use: { baseURL: `http://127.0.0.1:${PORT}`, trace: "off", video: "off" },
  webServer: {
    // Production build only. `next dev` does not reproduce this.
    command: `npx next start -p ${PORT}`,
    url: `http://127.0.0.1:${PORT}/`,
    // Must be false: on a loaded machine a killed server can outlive the port
    // check, and a reused old server would be measured under the new label.
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
