import assert from "node:assert/strict";
import {remoteInputs, remoteInputForPlan} from "./remote-input.js";
import {remoteArrivalMetrics} from "./remote-arrivals.js";
import {BRAND_ARRIVAL_INTERVAL_MS, type BrandArrival}
  from "./arrival-runner.js";
import {remotePlans, requestedPlan, remoteRunKey, remoteSeasonPolicy,
  outputRoot, remotePolicy, REMOTE_RETRY, validateCampaign,
  type RemoteCampaign, type RemotePlan} from "./remote-contract.js";
import type {ConnectedInput} from "./reuse-input.js";
import type {SeasonEvent, SeasonRecord} from "./season-runner.js";
import {REMOTE_GOLDEN_PROFILE, assertRemoteGoldenRuntime}
  from "./remote-golden-profile.js";

type Row = Record<string, unknown>;
function row(value: unknown): Row {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  return value as Row;
}
function nonnegative(value: unknown): number {
  assert.ok(typeof value === "number" && Number.isFinite(value) && value >= 0);
  return value;
}
export type RemoteSample = {
  id: string; plan: RemotePlan; status: string;
  wallMs: number | null; firstSeasonMs: number | null;
  firstBrandMs: number | null; memoryMaxRatio: number | null;
  runtime: {revision: string; node: string; platform: string; arch: string};
  counts: Record<string, number>; elapsedMs: number;
  brands: ReturnType<typeof remoteArrivalMetrics>["brands"];
  seasonPeak: number | null;
};

// 저장한 원본 증거를 다시 검사한다. HTTP 성공만으로 성능 표본을 채택하지 않는다.
export function readRemoteSample(campaign: RemoteCampaign,
  baseInput: ConnectedInput, value: unknown): RemoteSample {
  validateCampaign(campaign);
  const e = row(value);
  assert.equal(e.version, 5);
  assert.equal(e.scope, "development-connected-experiment");
  assert.equal(e.goldenProfile, REMOTE_GOLDEN_PROFILE.id);
  assert.deepEqual(e.campaign, campaign);
  const plan = requestedPlan({runID: row(e.plan).id});
  assert.deepEqual(e.plan, plan);
  const input = remoteInputForPlan(baseInput, plan);
  const items = remoteInputs(plan);
  assert.deepEqual(e.inputs, items);
  assert.deepEqual(e.policy, remotePolicy(plan));
  assert.deepEqual(e.seasonPolicy, remoteSeasonPolicy(plan));
  assert.equal(e.arrivalIntervalMs, BRAND_ARRIVAL_INTERVAL_MS);
  assert.equal(e.key, remoteRunKey(campaign, plan));
  assert.deepEqual(e.retry, REMOTE_RETRY);
  assert.ok(typeof e.status === "string" &&
    ["succeeded", "failed", "aborted", "stopped", "unavailable"]
      .includes(e.status));
  const elapsedMs = nonnegative(e.endedAt) - nonnegative(e.startedAt);
  assert.ok(elapsedMs >= 0);
  const counts = Object.fromEntries(Object.entries(row(e.counts)).map(
    ([key, value]) => {
      assert.ok(Number.isSafeInteger(nonnegative(value)));
      return [key, value as number];
    }));
  for (const key of ["imageGET", "receivedBytes", "uploadCalls",
    "uploadedBytes", "objectReads", "objectReadBytes", "documentReads",
    "documentWrites"]) assert.ok(Object.hasOwn(counts, key));
  const runtime = row(e.runtime);
  for (const v of [e.revision, e.instanceID, runtime.node,
    runtime.platform, runtime.arch]) assert.ok(typeof v === "string" && v);
  const memory = row(e.memory);
  const memoryMaxRatio = memory.maxRatio === null ? null :
    nonnegative(memory.maxRatio);
  let wallMs: number | null = null;
  let firstSeasonMs: number | null = null;
  let firstBrandMs: number | null = null;
  let brands: RemoteSample["brands"] = [];
  let seasonPeak: number | null = null;
  if (e.status === "succeeded") {
    assertRemoteGoldenRuntime({platform: runtime.platform, arch: runtime.arch,
      encoder: runtime.encoder});
    assert.equal(e.error, null); assert.equal(e.fatalError, null);
    assert.equal(memory.stop, null);
    assert.equal(memory.limitBytes, 2 * 2**30);
    assert.equal(memory.thresholdRatio, 0.85);
    assert.equal(memory.sustainedMs, 1000);
    assert.equal(memory.sampleIntervalMs, 100);
    assert.equal(memory.maxSampleGapMs, 500);
    assert.ok(nonnegative(memory.samples) > 0 && memoryMaxRatio !== null);
    assert.equal(row(e.buffers).objects, 0);
    assert.equal(row(e.cache).openScopes, 0);
    assert.equal(row(e.cache).retainedBytes, 0);
    for (const [stage, slot] of Object.entries(row(e.slots))) {
      assert.equal(row(slot).active, 0); assert.equal(row(slot).queued, 0);
      const limits = remotePolicy(plan).limits;
      assert.ok(Object.hasOwn(limits, stage));
      const limit = limits[stage as keyof typeof limits];
      assert.equal(row(slot).limit, limit);
      if (limit !== null) assert.ok(nonnegative(row(slot).peakActive) <= limit);
    }
    assert.deepEqual(Object.keys(row(e.slots)).sort(),
      Object.keys(remotePolicy(plan).limits).sort());
    const m = row(e.measurement);
    assert.ok(Array.isArray(m.seasons) && Array.isArray(m.events) &&
      Array.isArray(m.arrivals));
    const seasons = m.seasons as SeasonRecord[];
    assert.ok(seasons.every((s) => s.status === "succeeded"));
    const origin = nonnegative(m.originMs);
    const metrics = remoteArrivalMetrics(items, seasons,
      m.events as SeasonEvent[], origin,
      remoteSeasonPolicy(plan).order === "serial-brands",
      m.arrivals as BrandArrival[], remoteSeasonPolicy(plan).concurrency);
    assert.deepEqual(m.brands, metrics.brands);
    assert.equal(m.seasonPeak, metrics.seasonPeak);
    brands = metrics.brands; seasonPeak = metrics.seasonPeak;
    assert.equal(m.firstBrandMs, metrics.firstBrandMs);
    assert.equal(m.firstSeasonMs, seasons[0].attempts.at(-1)!.endedMs - origin);
    wallMs = nonnegative(m.wallMs);
    firstSeasonMs = nonnegative(m.firstSeasonMs);
    firstBrandMs = nonnegative(m.firstBrandMs);
    assert.ok(wallMs > 0 && firstSeasonMs <= wallMs && firstBrandMs <= wallMs);
    for (const event of m.events as SeasonEvent[]) {
      assert.ok(event.atMs - origin <= wallMs);
    }
    for (const arrival of m.arrivals as BrandArrival[]) {
      assert.ok(arrival.arrivedMs !== null &&
        arrival.arrivedMs - origin <= wallMs);
    }
    assert.ok(Array.isArray(e.reports) && e.reports.length === 1);
    const measurement = row(row(e.reports[0]).measurement);
    assert.equal(measurement.complete, true);
    assert.equal(measurement.operationOutcome, "returned");
    const files: Array<[string, {bytes: number; sha256: string}]> = [];
    const paths: Array<[string, {thumbPath: string; detailPath: string}]> = [];
    for (const item of items) {
      const source = input.seasons.find((s) => s.seasonID === item.id)!;
      const unique = [...new Map(source.images.map((i) =>
        [i.sha256, i])).values()];
      const cover = input.covers.find((c) => c.seasonID === item.id)!;
      const golden = input.golden.find((g) => g.seasonID === item.id)!;
      [...unique, cover].forEach((image, index) => {
        const root = `${outputRoot(campaign, plan)}${item.id}-${index}/`;
        for (const variant of ["thumb", "detail"] as const) {
          const maxPixel = index === unique.length ?
            variant === "thumb" ? 512 : 1600 :
            variant === "thumb" ? 768 : 1920;
          const expected = golden.outputs.find((o) =>
            o.kind === (index === unique.length ? "cover" : "post") &&
            o.sourceHash === image.sha256 && o.maxPixel === maxPixel);
          assert.ok(expected);
          files.push([`${root}${variant}.jpg`,
            {bytes: expected.bytes, sha256: expected.sha256}]);
        }
        paths.push([`lookbookImportPerformanceRuns/${e.key}/assets/` +
          `${item.id}-${index}`, {thumbPath: `${root}thumb.jpg`,
          detailPath: `${root}detail.jpg`}]);
      });
    }
    assert.ok(Array.isArray(e.files) && Array.isArray(e.paths));
    const sort = (entries: unknown[]) => [...entries].sort((a, b) =>
      String((a as unknown[])[0]).localeCompare(String((b as unknown[])[0])));
    assert.deepEqual(sort(e.files), sort(files));
    assert.deepEqual(sort(e.paths), sort(paths));
    assert.ok(counts.objectReads >= files.length);
    assert.ok(counts.documentWrites >= paths.length * 2);
  }
  return {id: plan.id, plan, status: e.status, wallMs, firstSeasonMs,
    firstBrandMs, memoryMaxRatio, elapsedMs, counts, brands, seasonPeak,
    runtime: {revision: e.revision as string, node: runtime.node as string,
      platform: runtime.platform as string, arch: runtime.arch as string}};
}

export function remoteStatistics(samples: RemoteSample[],
  unconfirmed: string[] = []) {
  const plans = remotePlans();
  const seen = new Set<string>();
  for (const sample of samples) {
    assert.deepEqual(sample.plan, requestedPlan({runID: sample.id}));
    assert.ok(!seen.has(sample.id)); seen.add(sample.id);
  }
  assert.equal(new Set(unconfirmed).size, unconfirmed.length);
  for (const id of unconfirmed) {
    requestedPlan({runID: id}); assert.ok(!seen.has(id));
  }
  const groups = plans.filter((p) => p.purpose === "comparison").map((plan) => {
    const own = samples.filter((s) => s.plan.purpose === "comparison" &&
      s.id === plan.id);
    const success = own.filter((s) => s.status === "succeeded");
    const unknown = unconfirmed.filter((id) =>
      id === plan.id);
    const observed = success[0];
    return {variant: plan.variant, id: plan.id, arm: plan.arm,
      planned: 1, recorded: own.length, succeeded: success.length,
      unconfirmed: unknown, notRun: 1 - own.length - unknown.length,
      statuses: own.map((s) =>
        ({id: s.id, status: s.status})),
      observed: observed ? {wallMs: observed.wallMs,
        firstSeasonMs: observed.firstSeasonMs,
        firstBrandMs: observed.firstBrandMs,
        memoryMaxRatio: observed.memoryMaxRatio,
        brands: observed.brands, seasonPeak: observed.seasonPeak} : null};
  });
  const candidates = plans.filter((p) => p.purpose === "comparison" &&
    p.variant !== "S6");
  const comparisons = candidates.map((plan) => {
    const find = (name: string) => samples.find((s) =>
      s.plan.variant === name && s.plan.purpose === "comparison" &&
      s.status === "succeeded");
    const base = find("S6"); const candidate = find(plan.variant);
    const comparable = Boolean(base && candidate &&
      JSON.stringify(base.runtime) === JSON.stringify(candidate.runtime));
    const compare = (key: "wallMs" | "firstSeasonMs" | "firstBrandMs") =>
      comparable ? {baselineMs: base![key]!, candidateMs: candidate![key]!,
        changePercent: base![key]! > 0 ?
          (candidate![key]! / base![key]! - 1) * 100 : null} : null;
    return {variant: plan.variant, baseline: "S6", comparable,
      wall: compare("wallMs"),
      firstSeason: compare("firstSeasonMs"),
      firstBrand: compare("firstBrandMs")};
  });
  // 단일 관측은 후보 탐색 자료다. 채택·실패율·반복 악화 판정을 만들지 않는다.
  return {mode: "screening" as const, adoption: "not-assessed" as const,
    repeatedRegression: "not-assessed" as const,
    failureRateImprovement: "not-assessed" as const,
    planned: plans.length, recorded: samples.length,
    unconfirmed,
    notRun: plans.filter((p) => !seen.has(p.id) &&
      !unconfirmed.includes(p.id)).map((p) => p.id),
    smoke: samples.find((s) => s.plan.purpose === "smoke")?.status ??
      (unconfirmed.includes(plans[0].id) ? "unconfirmed" : "notRun"),
    groups, comparisons};
}
