import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {readFile} from "node:fs/promises";
import {resolve, sep} from "node:path";
import {setTimeout as delay} from "node:timers/promises";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {OperationEvents, readResourceReading, ResourceFeed}
  from "./resource-feed.js";

export const PREPARATION_DIGEST =
  "6f57fcafcbb3711f97504e24565768a694e3a824410a99ddd6a450d1f4196444";
export const preparationHash = (value: Buffer | string) =>
  createHash("sha256").update(value).digest("hex");
export type PreparationSource = {
  sourceRevision: string; sourceDigest: string; imageID: string;
};
export type PreparationPlan = PreparationSource & {
  version: 1; id: string; caseID: string; repeat: number;
  overlap: boolean; corpusDigest: string;
};
type PreparationCase = {
  id: string;
  image: {seasonID: string; kind: string; path: string; sha256: string;
    bytes: number; format: string; width: number; height: number;
    channels: number; depth: string; pages: number};
  golden: Array<{maxPixel: number; sha256: string; bytes: number;
    width: number; height: number}>;
};
export const PREPARATION_CASES = ["median-jpeg", "largest-pixels-jpeg",
  "largest-file-jpeg", "rgba-png", "largest-cover"] as const;

export function preparationPlans(source: PreparationSource): PreparationPlan[] {
  assert.match(source.sourceRevision, /^[a-f0-9]{40}$/);
  assert.match(source.sourceDigest, /^[a-f0-9]{64}$/);
  assert.match(source.imageID, /^sha256:[a-f0-9]{64}$/);
  const plans: PreparationPlan[] = [];
  for (let repeat = 1; repeat <= 3; repeat++) {
    const order = PREPARATION_CASES.map((_, i) =>
      PREPARATION_CASES[(i + repeat - 1) % PREPARATION_CASES.length]);
    for (const caseID of [...order, "overlap"]) {
      plans.push({...source, version: 1,
        id: `memory-${caseID}-${repeat}`,
        caseID: caseID === "overlap" ? "largest-pixels-jpeg" : caseID,
        repeat, overlap: caseID === "overlap",
        corpusDigest: PREPARATION_DIGEST});
    }
  }
  return plans;
}
export function validatePreparationPlan(plan: PreparationPlan): void {
  assert.deepEqual(plan, preparationPlans({sourceRevision: plan.sourceRevision,
    sourceDigest: plan.sourceDigest, imageID: plan.imageID})
    .find((value) => value.id === plan.id));
}
export function preparationCorpus(): PreparationCase[] {
  const bytes = readFileSync(new URL(
    "../../fixtures/performance-memory-preparation.json", import.meta.url));
  assert.equal(preparationHash(bytes), PREPARATION_DIGEST);
  const value = JSON.parse(bytes.toString());
  assert.deepEqual(value.cases.map((c: PreparationCase) => c.id),
    PREPARATION_CASES);
  return value.cases;
}
export async function preparationInput(root: string, item: PreparationCase) {
  const path = resolve(root, item.image.path);
  assert.ok(path.startsWith(resolve(root) + sep));
  const bytes = await readFile(path);
  assert.equal(bytes.length, item.image.bytes);
  assert.equal(preparationHash(bytes), item.image.sha256);
  return bytes;
}

export async function measurePreparation(plan: PreparationPlan, root: string) {
  validatePreparationPlan(plan);
  const item = (await preparationCorpus()).find((c) => c.id === plan.caseID);
  assert.ok(item);
  const started = performance.now();
  const now = () => performance.now() - started;
  const feed = new ResourceFeed(0);
  const abort = new AbortController();
  const operations = new OperationEvents();
  const sources: Buffer[] = [];
  const outputs: Buffer[] = [];
  const files: Array<{id: string; sha256: string; bytes: number}> = [];
  const samples: Array<ReturnType<ResourceFeed["consume"]> & {
    rssBytes: number; logicalBytes: number; marker: string;
    sharp: ReturnType<typeof sharp.counters>;
  }> = [];
  const events: ReturnType<OperationEvents["drain"]> = [];
  let reason: string | null = null;
  const sample = (marker = "tick") => {
    try {
      if (samples.length >= 10000) throw new Error("sample-overflow");
      const snapshot = feed.consume(now(), readResourceReading());
      samples.push({...snapshot, marker, rssBytes: process.memoryUsage().rss,
        logicalBytes: [...sources, ...outputs]
          .reduce((n, b) => n + b.length, 0),
        sharp: sharp.counters()});
      events.push(...operations.drain());
    } catch (error) {
      reason ??= error instanceof Error ? error.message : "resource-error";
      abort.abort(new Error(reason));
    }
  };
  sample("startup");
  const timer = setInterval(() => sample(), 100);
  const timeout = setTimeout(() => {
    reason ??= "run-timeout";
    abort.abort(new Error(reason));
  }, 120000);
  let baselineAtMs: number | null = null;
  let endedAtMs: number | null = null;
  try {
    abort.signal.throwIfAborted();
    await delay(2100, undefined, {signal: abort.signal});
    sample("before-input");
    abort.signal.throwIfAborted();
    assert.equal(samples.at(-1)?.cpuReady, true);
    baselineAtMs = samples.at(-1)?.atMs ?? null;
    for (let i = 0; i < (plan.overlap ? 2 : 1); i++) {
      sources.push(await preparationInput(root, item));
    }
    assert.ok(!plan.overlap || sources[0].buffer !== sources[1].buffer);
    const metadata = await sharp(sources[0]).metadata();
    for (const key of ["width", "height", "channels", "format", "depth"] as
      const) assert.equal(metadata[key], item.image[key]);
    assert.equal(metadata.pages ?? 1, item.image.pages);
    sample("input-ready");
    const count = plan.overlap ? 4 : 2;
    const transform = async (index: number) => {
      const id = `transform-${index}`;
      const thumb = index % 2 === 0;
      const [pixel, quality] = item.image.kind === "cover" ?
        thumb ? [512, 75] : [1600, 88] : thumb ? [768, 82] : [1920, 90];
      const expected = item.golden.find((g) => g.maxPixel === pixel);
      assert.ok(expected);
      abort.signal.throwIfAborted();
      operations.start(id, now());
      sample("transform-start");
      try {
        abort.signal.throwIfAborted();
        const bytes = await jpegBytes(sources[Math.floor(index / 2)],
          pixel, quality);
        outputs.push(bytes);
        assert.equal(preparationHash(bytes), expected.sha256);
        assert.equal(bytes.length, expected.bytes);
        files.push({id, sha256: expected.sha256, bytes: bytes.length});
        operations.finish(id, now(), expected.width * expected.height,
          "succeeded");
        sample("transform-end");
        abort.signal.throwIfAborted();
      } catch (error) {
        if (operations.snapshot().find((v) => v.id === id)?.endedAt === null) {
          operations.finish(id, now(), 0,
            abort.signal.aborted ? "cancelled" : "failed");
        }
        throw error;
      }
    };
    for (let i = 0; i < count; i++) operations.queue(`transform-${i}`, now());
    if (plan.overlap) {
      const settled = await Promise.allSettled(Array.from({length: count},
        (_, index) => transform(index)));
      const failure = settled.find((value) => value.status === "rejected");
      if (failure?.status === "rejected") throw failure.reason;
    } else {
      for (let i = 0; i < count; i++) await transform(i);
    }
    sample("outputs-held");
    await delay(200, undefined, {signal: abort.signal});
    endedAtMs = now();
  } catch (error) {
    reason ??= error instanceof Error ? error.message : "operation-error";
  } finally {
    sources.length = 0;
    outputs.length = 0;
    sample("released");
    if (!abort.signal.aborted) await delay(1000);
    sample("settled");
    clearInterval(timer);
    clearTimeout(timeout);
    events.push(...operations.drain());
  }
  return {version: 1, plan, status: reason ? "failed" : "succeeded", reason,
    baselineAtMs, endedAtMs, feed: feed.snapshot(), samples, events,
    operations: operations.snapshot(), files, logicalBytesAfter: 0,
    runtime: {node: process.version, arch: process.arch,
      platform: process.platform,
      sharp: sharp.versions, concurrency: sharp.concurrency(),
      cache: sharp.cache()},
    elapsedMs: now()};
}
export type PreparationResult = Awaited<ReturnType<typeof measurePreparation>>;

export function validatePreparationResult(plan: PreparationPlan,
  value: PreparationResult): void {
  validatePreparationPlan(plan);
  assert.deepEqual(value.plan, plan);
  assert.equal(value.version, 1);
  assert.equal(value.status, "succeeded");
  assert.equal(value.reason, null);
  assert.equal(value.feed.failure, null);
  assert.equal(value.feed.memory.stop, null);
  assert.equal(value.feed.memory.limitBytes, 2 * 2**30);
  assert.ok(value.feed.maxSampleGapMs <= 500);
  assert.equal(value.logicalBytesAfter, 0);
  assert.ok(value.elapsedMs > 0 && value.elapsedMs <= 120000);
  const count = plan.overlap ? 4 : 2;
  assert.equal(value.operations.length, count);
  assert.equal(value.events.length, count);
  assert.equal(value.files.length, count);
  const item = preparationCorpus().find((c) => c.id === plan.caseID);
  assert.ok(item);
  const golden = [...item.golden].sort((a, b) => a.maxPixel - b.maxPixel);
  for (let i = 0; i < count; i++) {
    const id = `transform-${i}`;
    const expected: PreparationCase["golden"][number] = golden[i % 2];
    const file = value.files.find((f) => f.id === id);
    assert.deepEqual(file,
      {id, sha256: expected.sha256, bytes: expected.bytes});
    assert.equal(value.operations.find((o) => o.id === id)?.units,
      expected.width * expected.height);
  }
  assert.deepEqual(new Set(value.events.map((e) => e.id)),
    new Set(value.operations.map((e) => e.id)));
  assert.deepEqual([...value.events].sort((a, b) => a.id.localeCompare(b.id)),
    [...value.operations].sort((a, b) => a.id.localeCompare(b.id)));
  assert.ok(value.operations.every((o) => o.outcome === "succeeded" &&
    o.units > 0 && o.startedAt !== null && o.endedAt !== null &&
    o.queuedAt <= o.startedAt && o.startedAt <= o.endedAt));
  assert.equal(value.runtime.platform, "linux");
  assert.equal(value.runtime.arch, "arm64");
  assert.ok(value.samples.length >= 30);
  const replay = new ResourceFeed(0);
  for (let i = 0; i < value.samples.length; i++) {
    const s = value.samples[i];
    const computed = replay.consume(s.atMs, s.reading);
    assert.equal(s.cpuReady, computed.cpuReady);
    assert.equal(s.cpuRatio, computed.cpuRatio);
    assert.equal(s.throttled, computed.throttled);
    assert.equal(s.reading.cpuCapacity, 1);
    assert.equal(s.reading.memory.limitBytes, 2 * 2**30);
    assert.ok(Number.isFinite(s.reading.memory.usedBytes));
    if (i) {
      assert.ok(s.atMs > value.samples[i - 1].atMs &&
      s.atMs - value.samples[i - 1].atMs <= 500);
    }
  }
  assert.deepEqual(value.feed, replay.snapshot());
  for (const marker of ["startup", "before-input", "input-ready",
    "outputs-held", "released", "settled"]) {
    assert.ok(value.samples.some((s) => s.marker === marker));
  }
  assert.equal(value.samples.at(-1)?.logicalBytes, 0);
  assert.equal(value.baselineAtMs,
    value.samples.find((s) => s.marker === "before-input")?.atMs);
  assert.ok(value.baselineAtMs !== null && value.endedAtMs !== null &&
    value.endedAtMs >= value.baselineAtMs &&
    value.endedAtMs <= value.elapsedMs);
}
