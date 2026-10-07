import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {isDeepStrictEqual} from "node:util";
import {PipelineRuntime} from "../pipeline/resources.js";
import {BufferInventory} from "./buffer-inventory.js";
import {comparisonInputs, makeComparisonPlan} from "./comparison.js";
import {repeatedRegression} from "./comparison-report.js";
import {superviseMemory} from "./memory-supervisor.js";
import {validMemoryEvidence} from "./overhead.js";
import {median, validateResultSet, type PlannedRun, type RunResult}
  from "./result.js";
import type {connectedExecutor} from "./reuse-input.js";
import {PRESSURE_INPUT, validatePressureMetrics, type ReuseLoad}
  from "./reuse-contract.js";
import {runSeasons, type SeasonEvent, type SeasonRecord}
  from "./season-runner.js";
import {brandInputs, validateBrandPlan, type BrandLoad, type BrandOrder}
  from "./brand-comparison.js";
import {brandMetrics} from "./brand-metrics.js";
import type {BrandProgress} from "./brand-progress.js";
import {inspectSubmissionTrace, makeSubmissionPlan, submissionPolicy,
  type SubmissionArm} from "./submission-comparison.js";
import {SubmissionRuntime} from "./submission-runtime.js";
import {withMeasurement} from "./session.js";
import {largeSeasons} from "./large-input.js";
import {makeLargePlan, makeLargeControlPlan, makeLargeConfirmationPlan}
  from "./large-comparison.js";
import {analyzeReuseTrace, TracedPipeline, type ReuseTrace,
  type TraceEvent} from "./reuse-trace.js";

export const BUDGETS = ["off", "128", "256", "512", "all"] as const;
export const COVER_ARMS = ["off", "current", "prepared"] as const;
export const PRESSURE_BUDGETS = ["off", "16", "32", "64", "128"] as const;
type Budget = typeof BUDGETS[number] | typeof PRESSURE_BUDGETS[number];
export type ReusePlan = PlannedRun & {experiment: "reuse-comparison-v1";
  budget: Budget; repeat: number; diagnostic?: "asset-timeline-v1";
  coverComparison?: "cover-preparation-v1";
  arm?: typeof COVER_ARMS[number];
  loadPressure?: "load-pressure-v1"; load?: ReuseLoad;
  submission?: "submission-v1"; submissionArm?: SubmissionArm;
  largeInput?: "large-input-v1";
  largeControl?: "p4-off-prepared-v1";
  largeConfirmation?: "p4-reuse-five-pair-v1";
  brandComparison?: "brand-fifo-v1"; brandLoad?: BrandLoad;
  brandOrder?: BrandOrder;
  phase?: "confirmation" | "pressure"};
type Source = Pick<PlannedRun,
  "sourceRevision" | "sourceDigest" | "inputDigest">;
const limits = {download: 4, transform: 1, upload: 4, paths: null};
export function reusePolicy(budget: Budget) {
  assert.ok([...BUDGETS, ...PRESSURE_BUDGETS].includes(budget));
  return {assets: {kind: "refill" as const, concurrency: null},
    hashes: {kind: "refill" as const, concurrency: null}, limits: {...limits},
    ...(budget === "off" ? {} :
      {sourceBufferBudgetBytes: budget === "all" ? null :
        Number(budget) * 2**20})};
}
export function makeReusePlan(source: Source): ReusePlan[] {
  makeComparisonPlan(source);
  const identity = {sourceRevision: source.sourceRevision,
    sourceDigest: source.sourceDigest, inputDigest: source.inputDigest};
  return Array.from({length: 3}, (_, index) => BUDGETS.map((_, offset) => {
    const budget = BUDGETS[(index + offset) % BUDGETS.length];
    return {...identity, id: `reuse-${budget}-${index + 1}`,
      experiment: "reuse-comparison-v1" as const, budget, repeat: index + 1,
      mode: "local-connected" as const, measurementCount: 1,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        experiment: "reuse-comparison-v1", policy: reusePolicy(budget),
        seasons: comparisonInputs("six"), concurrency: 6})).digest("hex")};
  })).flat();
}
export function validateReusePlan(plan: ReusePlan): void {
  if (Object.hasOwn(plan, "brandComparison")) {
    validateBrandPlan(plan);
    return;
  }
  if (Object.hasOwn(plan, "largeConfirmation")) {
    assert.ok(isDeepStrictEqual(plan, makeLargeConfirmationPlan(plan)
      .find((expected) => expected.id === plan.id)));
    return;
  }
  const make = Object.hasOwn(plan, "largeControl") ? makeLargeControlPlan :
    Object.hasOwn(plan, "largeInput") ? makeLargePlan :
      Object.hasOwn(plan, "submission") ? makeSubmissionPlan :
        Object.hasOwn(plan, "loadPressure") ? makeLoadPressurePlan :
          Object.hasOwn(plan, "coverComparison") ?
            makeCoverPreparationPlan : Object.hasOwn(plan, "diagnostic") ?
              makeReuseDiagnosticPlan : makeReusePlan;
  assert.ok(isDeepStrictEqual(plan,
    make(plan).find((expected) => expected.id === plan.id)));
}
export function makeLoadPressurePlan(source: Source): ReusePlan[] {
  const base = makeReusePlan(source)[0];
  assert.equal(source.inputDigest, PRESSURE_INPUT);
  const plans: ReusePlan[] = [];
  const add = (phase: "confirmation" | "pressure", load: ReuseLoad,
    budget: Budget, repeat: number) => {
    const settings = {loadPressure: "load-pressure-v1" as const, phase,
      load, budget, arm: budget === "off" ? "off" as const :
        "prepared" as const, diagnostic: "asset-timeline-v1" as const};
    plans.push({...base, ...settings, repeat,
      id: `load-pressure-${phase}-${load}-${budget}-${repeat}`,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        ...settings, policy: reusePolicy(budget),
        inputs: comparisonInputs(load),
        concurrency: 6, inputDigest: PRESSURE_INPUT})).digest("hex")});
  };
  for (let repeat = 1; repeat <= 5; repeat++) {
    const loads = ["single", "synthetic-three"] as const;
    for (let offset = 0; offset < 2; offset++) {
      const load = loads[(repeat - 1 + offset) % 2];
      const budgets = (repeat + loads.indexOf(load)) % 2 === 1 ?
        ["off", "256"] as const : ["256", "off"] as const;
      for (const budget of budgets) add("confirmation", load, budget, repeat);
    }
  }
  for (let repeat = 1; repeat <= 5; repeat++) {
    for (let offset = 0; offset < PRESSURE_BUDGETS.length; offset++) {
      add("pressure", "six", PRESSURE_BUDGETS[
        (repeat - 1 + offset) % PRESSURE_BUDGETS.length], repeat);
    }
  }
  return plans;
}
export function makeCoverPreparationPlan(source: Source): ReusePlan[] {
  const base = makeReusePlan(source);
  return Array.from({length: 5}, (_, index) => COVER_ARMS.map((_, offset) => {
    const arm = COVER_ARMS[(index + offset) % COVER_ARMS.length];
    const budget = arm === "off" ? "off" : "256";
    const plan = base.find((p) => p.budget === budget && p.repeat === 1);
    assert.ok(plan);
    return {...plan, id: `cover-${arm}-${index + 1}`, repeat: index + 1,
      coverComparison: "cover-preparation-v1" as const, arm,
      diagnostic: "asset-timeline-v1" as const,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        base: plan.settingsDigest, experiment: "cover-preparation-v1", arm,
        diagnostic: "asset-timeline-v1"})).digest("hex")};
  })).flat();
}
export function makeReuseDiagnosticPlan(source: Source): ReusePlan[] {
  return makeReusePlan(source).filter((p) => p.repeat === 1 &&
    ["off", "256"].includes(p.budget)).map((p) => ({...p,
    id: `diagnostic-${p.id}`, diagnostic: "asset-timeline-v1",
    settingsDigest: createHash("sha256").update(JSON.stringify({
      base: p.settingsDigest, diagnostic: "asset-timeline-v1"})).digest("hex"),
  }));
}
export async function runReuse(plan: ReusePlan,
  execute: ReturnType<typeof connectedExecutor>,
  memoryOptions?: Parameters<typeof superviseMemory>[1], trace?: ReuseTrace,
  progress?: BrandProgress) {
  validateReusePlan(plan);
  assert.equal(Boolean(plan.diagnostic), Boolean(trace));
  const reports: unknown[] = [];
  const buffers = new BufferInventory();
  let detail: unknown = null;
  let runtime: PipelineRuntime | undefined;
  let wallMs: number | null = null;
  const inputs = plan.brandComparison ? brandInputs(plan.brandLoad!) :
    plan.largeInput ? largeSeasons() :
      comparisonInputs(plan.load ?? "six");
  const submission = !!(plan.submission || plan.largeInput);
  const supervised = await superviseMemory(async (memorySignal) => {
    const signal = progress ? AbortSignal.any([memorySignal,
      progress.controller.signal]) : memorySignal;
    if (submission) assert.ok(plan.submissionArm);
    const config = {...(submission ? submissionPolicy(plan.budget,
      plan.submissionArm ?? "U") : reusePolicy(plan.budget)), signal};
    runtime = submission && trace ? new SubmissionRuntime(config,
      trace, plan.submissionArm === "P4") : trace ?
      new TracedPipeline(config, trace) :
      new PipelineRuntime(config);
    const pipeline = runtime;
    const events: SeasonEvent[] = [];
    const started = performance.now();
    if (progress) await progress.emit({event: "measurement-start"});
    const seasons = await buffers.run(() => withMeasurement({enabled: true,
      ...plan, instanceID: plan.id, emit: (report) => reports.push(report)},
    "local-connected", () => runSeasons(inputs,
      {order: plan.brandOrder ?? "parallel", concurrency: 6},
      (season) => pipeline instanceof SubmissionRuntime ?
        pipeline.withSeason(inputs.findIndex((s) =>
          s.id === season.id), () => execute(season, pipeline, signal)) :
        execute(season, pipeline, signal), {signal,
        ...(plan.brandComparison ? {onEvent: async (event: SeasonEvent) => {
          events.push(event);
          await progress?.emit(event);
        }} : {})})));
    wallMs = performance.now() - started;
    const firstEnded = seasons[0].attempts.at(-1)?.endedMs;
    detail = {seasons, ...(plan.brandComparison ? {originMs: started,
      brandEvents: events, ...brandMetrics(inputs, seasons, events, started,
        plan.brandOrder === "serial-brands")} : {}),
    firstSeasonMs: firstEnded === undefined ? null :
      firstEnded - started, ...(submission ? {
      seasonCompletedMs: seasons.map((s) => ({id: s.id,
        elapsedMs: (s.attempts.at(-1)?.endedMs ?? started) - started})),
    } : {})};
    assert.ok(seasons.every((season) => season.status === "succeeded"));
    assert.equal(buffers.snapshot().objects, 0);
    assert.equal(runtime.sourceBuffers?.snapshot().retainedBytes ?? 0, 0);
    assert.equal(runtime.sourceBuffers?.snapshot().openScopes ?? 0, 0);
  }, memoryOptions ?? {maxSampleGapMs: 500});
  await progress?.drain();
  const succeeded = supervised.status === "completed";
  const result: RunResult = {...plan, reports, wallMs,
    outcome: succeeded ? "succeeded" : supervised.status === "unavailable" ?
      "unavailable" : supervised.status === "stopped" ? "aborted" : "failed",
    correct: succeeded ? true : null,
    reason: succeeded ? null : supervised.memory.stop?.reason ?? "operation"};
  return {id: plan.id, measurementEnabled: true, results: [result], detail,
    ...(progress?.errorCode ? {evidenceError: progress.errorCode} : {}),
    ...(trace ? {trace: trace.snapshot()} : {}),
    cache: runtime?.sourceBuffers?.snapshot() ?? null,
    buffers: buffers.snapshot(), slots: runtime?.snapshot() ?? null,
    memory: supervised.memory, validation: validateResultSet([plan], [result])};
}

type Row = Record<string, unknown>;
function object(value: unknown): value is Row {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
export function validateReusePayload(plan: ReusePlan, value: unknown): boolean {
  try {
    validateReusePlan(plan);
    assert.ok(object(value) && value.id === plan.id &&
      value.measurementEnabled === true && Array.isArray(value.results));
    const validated = validateResultSet([plan], value.results);
    assert.ok(validated.valid && validated.eligibleIDs.length === 1);
    assert.ok(validMemoryEvidence(value.memory));
    const result = value.results[0] as RunResult;
    const report = result.reports[0] as {measurement: {stages:
      Record<string, {succeeded: number; receivedBytes: number;
        completedBytes: number}>}};
    const stages = report.measurement.stages;
    const off = plan.budget === "off";
    const inputs = plan.brandComparison ? brandInputs(plan.brandLoad!) :
      plan.largeInput ? largeSeasons() :
        comparisonInputs(plan.load ?? "six");
    if (plan.loadPressure || plan.submission || plan.largeInput) {
      validatePressureMetrics(plan, value, stages);
      if (plan.submission || plan.largeInput) {
        assert.ok(plan.submissionArm);
        inspectSubmissionTrace(value.trace as TraceEvent[],
        value.inputContract as Parameters<typeof inspectSubmissionTrace>[1],
        plan.submissionArm);
      }
    } else {
      if (plan.diagnostic) {
        const trace = analyzeReuseTrace(value.trace as TraceEvent[]);
        assert.equal(trace.reused, off ? 0 : 131);
        assert.equal(trace.prepared, plan.arm === "prepared" ? 6 : 0);
      } else assert.equal(Object.hasOwn(value, "trace"), false);
      assert.equal(stages["image.download"].succeeded, off ? 269 : 138);
      assert.equal(stages["image.download"].receivedBytes,
        off ? 223800086 : 112771684);
      assert.equal(stages["image.transform"].succeeded, 274);
      assert.equal(stages["file.upload"].succeeded, 274);
      assert.equal(stages["file.upload"].completedBytes, 42259800);
      assert.equal(stages["paths.save"].succeeded, 137);
    }
    assert.ok(object(value.detail) && Array.isArray(value.detail.seasons));
    assert.deepEqual(value.detail.seasons.map((s: Row) => [s.id, s.status]),
      inputs.map((s) => [s.id, "succeeded"]));
    if (plan.brandComparison) {
      assert.equal(Object.hasOwn(value, "evidenceError"), false);
      const metrics = brandMetrics(inputs,
        value.detail.seasons as SeasonRecord[],
        value.detail.brandEvents as SeasonEvent[],
        Number(value.detail.originMs),
        plan.brandOrder === "serial-brands");
      assert.deepEqual(value.detail.brands, metrics.brands);
      assert.equal(value.detail.firstBrandMs, metrics.firstBrandMs);
      assert.ok(metrics.brands.every((b) => b.completedMs !== null &&
        b.completedMs > 0 && b.completedMs <= Number(result.wallMs)));
    }
    if (plan.loadPressure || plan.submission || plan.largeInput) {
      assert.deepEqual(value.detail.seasons.map((s: Row) =>
        s.brandID), inputs.map((s) => s.brandID));
    }
    assert.ok(typeof value.detail.firstSeasonMs === "number" &&
      Number.isFinite(value.detail.firstSeasonMs) &&
      value.detail.firstSeasonMs > 0 &&
      value.detail.firstSeasonMs <= Number(result.wallMs));
    if (plan.submission || plan.largeInput) {
      assert.ok(Array.isArray(value.detail.seasonCompletedMs));
      const times = value.detail.seasonCompletedMs as Row[];
      assert.deepEqual(times.map((s) => s.id), inputs
        .map((s) => s.id));
      assert.equal(times[0].elapsedMs, value.detail.firstSeasonMs);
      const records = value.detail.seasons as Array<{attempts:
        Array<{endedMs: number}>}>;
      const firstAttempt = records[0].attempts.at(-1);
      assert.ok(firstAttempt);
      const origin = firstAttempt.endedMs -
        Number(times[0].elapsedMs);
      times.forEach((time, i) => {
        assert.ok(typeof time.elapsedMs === "number" &&
          Number.isFinite(time.elapsedMs) && time.elapsedMs > 0 &&
          time.elapsedMs <= Number(result.wallMs));
        const attempt = records[i].attempts.at(-1);
        assert.ok(attempt);
        assert.ok(Math.abs(attempt.endedMs - origin -
          Number(time.elapsedMs)) < 0.001);
      });
    }
    assert.ok(object(value.buffers) && value.buffers.objects === 0 &&
      value.buffers.currentBytes === 0 && object(value.slots));
    for (const [stage, limit] of Object.entries(limits)) {
      const slot = value.slots[stage];
      assert.ok(object(slot) && slot.limit === limit && slot.active === 0 &&
        slot.queued === 0);
    }
    if (plan.loadPressure || plan.submission || plan.largeInput) return true;
    if (off) assert.equal(value.cache, null);
    else {
      const cache = value.cache;
      assert.ok(object(cache));
      assert.equal(cache.budgetBytes, plan.budget === "all" ? null :
        Number(plan.budget) * 2**20);
      assert.equal(cache.retainedBytes, 0);
      assert.equal(cache.openScopes, 0);
      assert.equal(cache.hits, 131);
      assert.equal(cache.misses, plan.arm === "prepared" ? 0 : 6);
      assert.equal(cache.rejectedByBudget, 0);
      assert.ok(Number.isSafeInteger(cache.peakRetainedBytes) &&
        Number(cache.peakRetainedBytes) > 0 &&
        Number(cache.peakRetainedBytes) <= 112771684);
    }
    return true;
  } catch {
    return false;
  }
}

export function summarizeReuse(plans: ReusePlan[], rows: unknown[]) {
  const issues: string[] = [];
  const diagnostic = !!plans[0] && Object.hasOwn(plans[0], "diagnostic");
  const cover = !!plans[0] && Object.hasOwn(plans[0], "coverComparison");
  const pressure = !!plans[0] && Object.hasOwn(plans[0], "loadPressure");
  const submission = !!plans[0] && Object.hasOwn(plans[0], "submission");
  const make = submission ? makeSubmissionPlan : pressure ?
    makeLoadPressurePlan : cover ?
      makeCoverPreparationPlan : diagnostic ?
        makeReuseDiagnosticPlan : makeReusePlan;
  if (!plans[0] || !isDeepStrictEqual(plans, make(plans[0]))) {
    issues.push("plan.matrix");
  }
  const seen = new Set<string>();
  const images = new Set<string>();
  const counts = {succeeded: 0, failed: 0, aborted: 0, unavailable: 0};
  const times = new Map<string, number[]>();
  const paired = new Map<string, {wall: number; first: number}>();
  const pressureRuns = new Map<string, boolean[]>();
  const groupKey = (p: ReusePlan) => submission ?
    `${p.submissionArm}/${p.budget}` : pressure ?
      `${p.phase}/${p.load}/${p.budget}` : cover ? String(p.arm) : p.budget;
  for (const row of rows) {
    if (!object(row) || typeof row.id !== "string" || seen.has(row.id)) {
      issues.push("result.schema-or-duplicate");
      continue;
    }
    const plan = plans.find((p) => p.id === row.id);
    if (!plan) {
      issues.push("result.unknown");
      continue;
    }
    seen.add(row.id);
    if (typeof row.imageID !== "string" ||
      !/^sha256:[a-f0-9]{64}$/.test(row.imageID)) issues.push("result.image");
    else images.add(row.imageID);
    if (!Object.hasOwn(counts, String(row.verdict))) {
      issues.push("result.verdict");
      continue;
    }
    counts[row.verdict as keyof typeof counts]++;
    if (row.verdict !== "succeeded") continue;
    if (!validateReusePayload(plan, row.payload) || !object(row.evidence) ||
      row.evidence.OOMKilled !== false || row.evidence.ExitCode !== 0 ||
      row.evidence.Status !== "exited" || row.evidence.Running !== false) {
      issues.push("result.false-success");
      continue;
    }
    const payload = row.payload as {results: RunResult[];
      detail: {firstSeasonMs: number}};
    const key = groupKey(plan);
    const group = times.get(key) ?? [];
    group.push(Number(payload.results[0].wallMs));
    times.set(key, group);
    paired.set(`${key}-${plan.repeat}`, {wall: Number(payload.results[0]
      .wallMs), first: payload.detail.firstSeasonMs});
    if (pressure || submission) {
      const cache = (row.payload as {cache: {rejectedByBudget: number;
        misses: number} | null}).cache;
      const samples = pressureRuns.get(key) ?? [];
      samples.push(!!cache && cache.rejectedByBudget > 0 && cache.misses > 0);
      pressureRuns.set(key, samples);
    }
  }
  if (seen.size !== plans.length) issues.push("result.missing");
  if (images.size !== 1) issues.push("result.mixed-image");
  const pressureComparisons = (pressure || submission) && !issues.length ?
    [...new Set(plans.map(groupKey))].map((group) => ({group,
      successes: times.get(group)?.length ?? 0,
      medianMs: times.get(group)?.length === 5 ? median(times.get(group) ??
        []) : null,
      pressureExpected: submission ? group.endsWith("/16") :
        /pressure\/six\/(16|32|64)$/.test(group),
      pressureEstablished: pressureRuns.get(group)?.length === 5 &&
        pressureRuns.get(group)?.every(Boolean) === true})) : [];
  const contrasts = pressureComparisons.filter((g) =>
    !g.group.endsWith("/off")).flatMap((g) => {
    const baselines = submission ? ["U/off", ...(!g.group.startsWith("U/") ?
      [`U/${g.group.split("/")[1]}`] : []),
    ...(/^(B4|P4)\//.test(g.group) ?
      [`R4/${g.group.split("/")[1]}`] : [])] :
      [g.group.replace(/\/[^/]+$/, "/off")];
    return baselines.map((baseline) => ({baseline, candidate: g.group}));
  });
  const pressureRegressions = (pressure || submission) && !issues.length ?
    contrasts.map(({baseline, candidate}) => {
      const pairs = Array.from({length: 5}, (_, i) => ({
        base: paired.get(`${baseline}-${i + 1}`),
        candidate: paired.get(`${candidate}-${i + 1}`)}));
      const complete = pairs.every((p) => p.base && p.candidate);
      const compare = (key: "wall" | "first") => complete ?
        repeatedRegression(pairs.map((p) => {
          assert.ok(p.base);
          return p.base[key];
        }), pairs.map((p) => {
          assert.ok(p.candidate);
          return p.candidate[key];
        })) : null;
      return {baseline, candidate, complete,
        pairs: pairs.filter((p) => p.base && p.candidate).length,
        wall: compare("wall"), first: compare("first")};
    }) : [];
  const regressions = cover && !issues.length ? ["off", "current"].map(
    (baseline) => {
      const pairs = Array.from({length: 5}, (_, i) => ({
        base: paired.get(`${baseline}-${i + 1}`),
        candidate: paired.get(`prepared-${i + 1}`)}));
      const complete = pairs.every((p) => p.base && p.candidate);
      const compare = (key: "wall" | "first") => {
        if (!complete) return null;
        return repeatedRegression(pairs.map((p) => {
          assert.ok(p.base);
          return p.base[key];
        }), pairs.map((p) => {
          assert.ok(p.candidate);
          return p.candidate[key];
        }));
      };
      return {baseline, candidate: "prepared", complete,
        pairs: pairs.filter((p) => p.base && p.candidate).length,
        wall: compare("wall"), first: compare("first")};
    }) : [];
  return {valid: issues.length === 0, issues, planned: plans.length,
    recorded: seen.size, counts, comparisons: pressure || submission ?
      pressureComparisons :
      issues.length ? [] :
        (cover ? COVER_ARMS : diagnostic ? ["off", "256"] as const : BUDGETS)
          .map((group) => ({...(cover ? {arm: group} : {budget: group}),
            successes: times.get(group)?.length ?? 0,
            medianMs: times.get(group)?.length === (cover ? 5 : diagnostic ?
              1 : 3) ? median(times.get(group) ?? []) : null})),
    regressions: pressure || submission ? pressureRegressions : regressions,
    scope: submission ? "six-season-submission-order-not-production-policy" :
      pressure ? "fixed-input-small-budget-pressure-not-large-input" :
        cover ? "six-season-five-pair-cover-comparison-not-full-adoption" :
          diagnostic ? "two-run-timeline-diagnosis-not-performance-adoption" :
            "local-connected-three-repeat-not-review-bypass-or-adoption"};
}
