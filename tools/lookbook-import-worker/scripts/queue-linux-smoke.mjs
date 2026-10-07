import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {readFileSync} from "node:fs";
import {setTimeout as delay} from "node:timers/promises";
import {chromium} from "playwright";
import {PipelineRuntime} from "../lib/pipeline/resources.js";
import {readContainerMemorySync, startResourceSampling} from
  "../lib/performance/resources.js";
import {BrowserImageGate} from "../lib/queue/browser-gate.js";
import {QueueSupervisor} from "../lib/queue/supervisor.js";

assert.equal(process.platform, "linux");
const memoryLimitBytes = 2 * 1024 * 1024 * 1024;
const initialMemory = readContainerMemorySync();
assert.equal(initialMemory?.source, "cgroup-v2");
assert.ok(initialMemory.limitBytes >= 1.8 * 1024 * 1024 * 1024);
assert.ok(initialMemory.limitBytes <= memoryLimitBytes);
const [quotaText, periodText] = readFileSync("/sys/fs/cgroup/cpu.max", "utf8")
  .trim().split(/\s+/);
const cpuQuota = Number(quotaText) / Number(periodText);
assert.ok(Number.isFinite(cpuQuota) && cpuQuota >= 0.9 && cpuQuota <= 1.1);

const pipeline = new PipelineRuntime({
  assets: {kind: "refill", concurrency: null},
  hashes: {kind: "refill", concurrency: 4},
  limits: {download: 4, transform: 1, upload: 4, paths: null},
  sourceBufferBudgetBytes: 128 * 1024 * 1024,
});
const store = pipeline.sourceBuffers;
assert.ok(store);
const scope = store.openScope();
const source = Buffer.from("queue linux browser transition source");
scope.retain("https://brand.example/image.jpg",
  "https://brand.example/lookbook", source);
const gate = new BrowserImageGate();
const unregisterCleanup = gate.registerBrowserTransitionCleanup(() =>
  store.clearRetained());

let releaseImage;
let imageStarted;
const imageStartedPromise = new Promise((resolve) => {
  imageStarted = resolve;
});
let firstImageActive = false;
const firstImage = gate.withImageWork(async () => {
  firstImageActive = true;
  imageStarted();
  await new Promise((resolve) => { releaseImage = resolve; });
  firstImageActive = false;
});
await imageStartedPromise;

let browserEntered = false;
let queuedImageEntered = false;
const sampling = {metrics: null, supervisor: null};
const browserTask = gate.withBrowserWork(async () => {
  browserEntered = true;
  assert.equal(gate.snapshot().activeImages, 0);
  assert.equal(store.snapshot().retainedBytes, 0);
  const browser = await chromium.launch({headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"]});
  try {
    const page = await browser.newPage();
    await page.setContent("<title>outpick queue linux smoke</title>");
    assert.equal(await page.title(), "outpick queue linux smoke");
    sampling.metrics = startResourceSampling();
    sampling.supervisor = new QueueSupervisor();
    await delay(1400);
  } finally {
    await browser.close();
  }
});

await waitFor(() => gate.snapshot().queuedBrowsers === 1,
  "browser did not queue behind active image work");
const secondImage = gate.withImageWork(async () => {
  queuedImageEntered = true;
});
await delay(50);
assert.equal(firstImageActive, true);
assert.equal(browserEntered, false);
assert.equal(queuedImageEntered, false);
releaseImage();
await Promise.all([firstImage, browserTask, secondImage]);
unregisterCleanup();
scope.close();

assert.equal(browserEntered, true);
assert.equal(queuedImageEntered, true);
assert.deepEqual(gate.snapshot(), {
  activeImages: 0, activeBrowser: false, queuedBrowsers: 0,
});
assert.equal(store.snapshot().openScopes, 0);
assert.equal(store.snapshot().retainedBytes, 0);

const metrics = await sampling.metrics.stop();
const supervisor = sampling.supervisor.stop();
assert.equal(metrics.containerMemoryAvailable, true);
assert.equal(metrics.containerSource, "cgroup-v2");
assert.ok(metrics.samples >= 8);
assert.ok(metrics.maxSampleGapMs <= 500);
assert.ok(metrics.maxContainerRatio < 0.85);
assert.equal(supervisor.memoryStop, null);
assert.equal(supervisor.admissionStop, null);
assert.ok(supervisor.sampleCount >= 8);

const child = await exerciseSigtermDrain();
const memoryPressure = await exerciseSustainedMemoryStop();
console.log(JSON.stringify({
  platform: process.platform,
  architecture: process.arch,
  cpuQuota,
  memoryLimitBytes: initialMemory.limitBytes,
  browserGate: gate.snapshot(),
  sourceBuffers: store.snapshot(),
  sample: {
    count: metrics.samples,
    maxGapMs: metrics.maxSampleGapMs,
    maxContainerRatio: metrics.maxContainerRatio,
    eventLoopMaxMs: metrics.eventLoopMaxMs,
  },
  supervisor,
  sigterm: child,
  memoryPressure,
}));

async function waitFor(predicate, description) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await delay(10);
  }
  throw new Error(description);
}

async function exerciseSigtermDrain() {
  const processHandle = spawn(process.execPath,
    ["scripts/queue-linux-sigterm-child.mjs"], {stdio: ["ignore", "pipe", "pipe"]});
  let output = "";
  let pending = "";
  const events = [];
  let readyResolve;
  let readyReject;
  let readySeen = false;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  let exitedResolve;
  const exited = new Promise((resolve) => { exitedResolve = resolve; });
  const timeout = setTimeout(() => {
    processHandle.kill("SIGKILL");
    readyReject(new Error(`SIGTERM browser child timed out: ${output}`));
  }, 45000);
  processHandle.stdout.setEncoding("utf8");
  processHandle.stderr.setEncoding("utf8");
  processHandle.stdout.on("data", (chunk) => {
    output += chunk;
    pending += chunk;
    for (;;) {
      const index = pending.indexOf("\n");
      if (index < 0) break;
      const line = pending.slice(0, index);
      pending = pending.slice(index + 1);
      if (!line) continue;
      const event = JSON.parse(line);
      events.push(event);
      if (event.type === "ready") {
        readySeen = true;
        readyResolve(event);
      }
    }
  });
  processHandle.stderr.on("data", (chunk) => { output += chunk; });
  processHandle.once("error", (error) => readyReject(error));
  processHandle.once("exit", (code, signal) => {
    exitedResolve({code, signal});
    if (!readySeen) {
      readyReject(new Error(`SIGTERM browser child exited before ready: ${output}`));
    }
  });

  let childExited = false;
  try {
    const readyEvent = await ready;
    assert.ok(Array.isArray(readyEvent.browserPIDs) &&
      readyEvent.browserPIDs.length > 0);
    assert.equal(processHandle.kill("SIGTERM"), true);
    const exit = await exited;
    childExited = true;
    assert.deepEqual(exit, {code: 0, signal: null}, output);
    const drained = events.find((event) => event.type === "drained");
    assert.ok(drained, output);
    assert.deepEqual(drained.gate, {
      activeImages: 0, activeBrowser: false, queuedBrowsers: 0,
    });
    assert.ok(events.some((event) => event.type === "browserProcessesExited"), output);
    return {exitCode: exit.code, browserPIDs: readyEvent.browserPIDs,
      browserPIDExited: true,
      gateDrained: drained.gate};
  } finally {
    clearTimeout(timeout);
    if (!childExited) processHandle.kill("SIGKILL");
  }
}

async function exerciseSustainedMemoryStop() {
  assert.equal(typeof global.gc, "function");
  const guarded = new QueueSupervisor();
  const blocks = [];
  const startedAt = Date.now();
  try {
    while (!guarded.signal.aborted && Date.now() - startedAt < 40000) {
      const block = Buffer.allocUnsafe(8 * 1024 * 1024);
      block.fill(0xa5);
      blocks.push(block);
      await delay(100);
    }
    const report = guarded.stop();
    assert.ok(guarded.signal.aborted, JSON.stringify(report));
    assert.match(report.memoryStop ?? "", /memory:sustained-high/);
    assert.ok((report.maxMemoryRatio ?? 0) >= 0.85);
    assert.ok((report.maxMemoryRatio ?? 1) < 0.92);
    return {memoryStop: report.memoryStop, maxRatio: report.maxMemoryRatio,
      samples: report.sampleCount, elapsedMs: Date.now() - startedAt};
  } finally {
    guarded.stop();
    blocks.length = 0;
    global.gc();
  }
}
