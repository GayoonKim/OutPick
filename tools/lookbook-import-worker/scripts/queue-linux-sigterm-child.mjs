import {chromium} from "playwright";
import assert from "node:assert/strict";
import {readdirSync, readFileSync} from "node:fs";
import {BrowserImageGate} from "../lib/queue/browser-gate.js";

const controller = new AbortController();
const gate = new BrowserImageGate();
process.once("SIGTERM", () => controller.abort(new Error("SIGTERM")));

await gate.withBrowserWork(async (signal) => {
  const browser = await chromium.launch({headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"]});
  const browserPIDs = listChromiumPIDs();
  assert.ok(browserPIDs.length > 0, "Chromium processes were not visible");
  let closeBrowser;
  const browserClosed = new Promise((resolve, reject) => {
    signal.addEventListener("abort", () => {
      closeBrowser = browser.close();
      closeBrowser.then(resolve, reject);
    }, {once: true});
  });
  const page = await browser.newPage();
  await page.setContent("<title>sigterm drain</title>");
  console.log(JSON.stringify({type: "ready", browserPIDs}));
  await browserClosed;
  await closeBrowser;
  await waitFor(() => browserPIDs.every((pid) => !processExists(pid)), 5000);
  console.log(JSON.stringify({type: "browserProcessesExited", browserPIDs}));
}, controller.signal);

console.log(JSON.stringify({type: "drained", gate: gate.snapshot()}));

function listChromiumPIDs() {
  return readdirSync("/proc", {withFileTypes: true})
    .filter((entry) => entry.isDirectory() && /^\d+$/.test(entry.name))
    .filter((entry) => {
      try {
        const command = readFileSync(`/proc/${entry.name}/cmdline`, "utf8");
        return command.includes("/ms-playwright/") && /chrome|chromium/i.test(command);
      } catch {
        return false;
      }
    })
    .map((entry) => Number(entry.name));
}

async function waitFor(predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Chromium process did not exit after SIGTERM");
}

function processExists(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const state = stat.slice(stat.lastIndexOf(")") + 2).split(/\s+/)[0];
    return state !== "Z";
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}
