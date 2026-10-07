import {type ComparisonPlan, phasePlans, runComparison}
  from "./comparison.js";
import {median, validateResultSet} from "./result.js";

export function overheadCases() {
  const cases = [{id: "warmup-off", enabled: false, warmup: true},
    {id: "warmup-on", enabled: true, warmup: true}];
  for (let pair = 1; pair <= 5; pair++) {
    for (const enabled of pair % 2 === 1 ? [false, true] : [true, false]) {
      cases.push({id: `pair-${pair}-${enabled ? "on" : "off"}`,
        enabled, warmup: false});
    }
  }
  return cases;
}

export async function runOverhead(plan: ComparisonPlan,
  execute: Parameters<typeof runComparison>[1],
  memoryOptions?: Parameters<typeof runComparison>[2],
  onCase?: (entry: ReturnType<typeof overheadCases>[number],
    result: Awaited<ReturnType<typeof runComparison>> | null)
    => Promise<void>) {
  if (plan.arm !== "A" || plan.load !== "single") {
    throw new Error("계측 오버헤드는 A 단일 시즌에서 비교합니다.");
  }
  const cases: Array<ReturnType<typeof overheadCases>[number] & {
    result: Awaited<ReturnType<typeof runComparison>> | null;
  }> = [];
  let failed = false;
  for (const entry of overheadCases()) {
    const result = failed ? null : await runComparison(plan, execute,
      memoryOptions, entry.enabled);
    cases.push({...entry, result});
    await onCase?.(entry, result);
    if (result && (result.validation.eligibleIDs.length !== 2 ||
      result.memory.stop !== null)) failed = true;
  }
  return {id: plan.id, purpose: "measurement-overhead", cases};
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function validMemoryEvidence(value: unknown): boolean {
  return object(value) && value.stop === null &&
    ["cgroup-v1", "cgroup-v2"].includes(String(value.source)) &&
    value.limitBytes === 2 * 2**30 && value.sampleIntervalMs === 100 &&
    value.maxSampleGapMs === 500 && value.thresholdRatio === 0.85 &&
    value.sustainedMs === 1000 && Number.isSafeInteger(value.samples) &&
    Number(value.samples) >= 2 && typeof value.maxRatio === "number" &&
    Number.isFinite(value.maxRatio) && value.maxRatio >= 0 &&
    typeof value.lastSampleMs === "number" &&
    Number.isFinite(value.lastSampleMs) && value.lastSampleMs >= 0;
}

export function assessOverhead(plan: ComparisonPlan, payload: unknown) {
  const issues: string[] = [];
  const expected = overheadCases();
  const times = new Map<string, number>();
  const measurementIDs = new Set<string>();
  if (!object(payload) || payload.id !== plan.id ||
    payload.purpose !== "measurement-overhead" ||
    !Array.isArray(payload.cases) || payload.cases.length !== 12) {
    return {valid: false, issues: ["cases.invalid"], comparison: null};
  }
  payload.cases.forEach((value: unknown, index: number) => {
    const entry = expected[index];
    if (!object(value) || value.id !== entry.id ||
      value.enabled !== entry.enabled || value.warmup !== entry.warmup ||
      !object(value.result) || value.result.id !== plan.id ||
      value.result.measurementEnabled !== entry.enabled ||
      !Array.isArray(value.result.results)) {
      issues.push(`${entry.id}.invalid`);
      return;
    }
    const rows = value.result.results;
    const valid = validateResultSet(phasePlans(plan, entry.enabled), rows);
    if (!valid.valid || valid.eligibleIDs.length !== 2 ||
      !validMemoryEvidence(value.result.memory)) {
      issues.push(`${entry.id}.failed`);
      return;
    }
    let wallMs = 0;
    for (const row of rows) {
      wallMs += Number(row.wallMs);
      for (const report of row.reports) {
        const id = report.measurement.runID;
        if (measurementIDs.has(id)) issues.push(`${entry.id}.reused-report`);
        measurementIDs.add(id);
      }
    }
    times.set(entry.id, wallMs);
  });
  if (issues.length) return {valid: false, issues, comparison: null};
  const pairs = Array.from({length: 5}, (_, index) => {
    const pair = index + 1;
    const off = times.get(`pair-${pair}-off`) ?? 0;
    const on = times.get(`pair-${pair}-on`) ?? 0;
    return {pair, offMs: off, onMs: on, changePercent: (on / off - 1) * 100};
  });
  const offMedianMs = median(pairs.map((pair) => pair.offMs));
  const onMedianMs = median(pairs.map((pair) => pair.onMs));
  return {valid: true, issues, comparison: {pairs, offMedianMs, onMedianMs,
    changePercent: (onMedianMs / offMedianMs - 1) * 100}};
}
