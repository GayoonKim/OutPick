import {STAGES, type MeasurementContext} from "./metrics.js";

export type PlannedRun = {
  id: string;
  sourceRevision: string;
  sourceDigest: string;
  inputDigest: string;
  settingsDigest: string;
  mode: MeasurementContext["mode"];
  measurementCount: number;
};
export type RunOutcome = "succeeded" | "failed" | "aborted" | "unavailable";
export type RunResult = {
  id: string;
  sourceDigest: string;
  inputDigest: string;
  settingsDigest: string;
  outcome: RunOutcome;
  reason: "operation" | "correctness" | "memory" | "environment" | null;
  correct: boolean | null;
  wallMs: number | null;
  reports: unknown[];
};

type ObjectValue = Record<string, unknown>;
function object(value: unknown): value is ObjectValue {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function nonnegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}
function count(value: unknown): value is number {
  return nonnegative(value) && Number.isSafeInteger(value);
}
function digest(value: unknown): boolean {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

// 원본 레코드는 그대로 보존하며 검증 실패를 성공 표본에서 제외한다.
export function validateResultSet(
  plan: PlannedRun[], results: unknown[],
): {
  valid: boolean; issues: string[]; planned: number; recorded: number;
  counts: Record<RunOutcome, number>; eligibleIDs: string[];
} {
  const issues: string[] = [];
  const counts: Record<RunOutcome, number> = {
    succeeded: 0, failed: 0, aborted: 0, unavailable: 0,
  };
  const eligibleIDs: string[] = [];
  const planned = new Map<string, PlannedRun>();
  if (plan.length === 0) issues.push("plan.empty");
  for (const run of plan) {
    if (!/^[a-zA-Z0-9_-]+$/.test(run.id) || planned.has(run.id) ||
      !digest(run.sourceDigest) || !digest(run.inputDigest) ||
      !digest(run.settingsDigest) || !count(run.measurementCount) ||
      !/^[a-f0-9]{7,64}$/.test(run.sourceRevision) ||
      !["task", "wake", "local-extraction", "local-assets", "local-connected"]
        .includes(run.mode)) {
      issues.push("plan.invalid");
    }
    planned.set(run.id, run);
  }
  const seen = new Set<string>();
  const measurementIDs = new Set<string>();
  results.forEach((value, index) => {
    const prefix = `result[${index}]`;
    if (!object(value) || typeof value.id !== "string") {
      issues.push(`${prefix}.schema`);
      return;
    }
    const expected = planned.get(value.id);
    if (!expected || seen.has(value.id)) {
      issues.push(`${prefix}.unexpected-or-duplicate`);
      return;
    }
    seen.add(value.id);
    const errors = validateRun(value, expected, measurementIDs);
    issues.push(...errors.map((error) => `${prefix}.${error}`));
    if (Object.hasOwn(counts, String(value.outcome))) {
      counts[value.outcome as RunOutcome] += 1;
    }
    if (errors.length === 0 && value.outcome === "succeeded") {
      eligibleIDs.push(value.id);
    }
  });
  if (seen.size !== planned.size) issues.push("results.missing");
  // 일부 정상 행이 있어도 누락·중복·계획 오류가 있는 집합은 비교하지 않는다.
  return {
    valid: issues.length === 0, issues,
    planned: plan.length, recorded: seen.size, counts,
    eligibleIDs: issues.length === 0 ? eligibleIDs : [],
  };
}

function validateRun(
  row: ObjectValue, plan: PlannedRun, measurementIDs: Set<string>,
): string[] {
  const errors: string[] = [];
  const identities = ["sourceDigest", "inputDigest", "settingsDigest"] as const;
  for (const key of identities) {
    if (row[key] !== plan[key]) errors.push(key);
  }
  if (!["succeeded", "failed", "aborted", "unavailable"].includes(
    String(row.outcome))) errors.push("outcome");
  const success = row.outcome === "succeeded";
  if (success) {
    if (row.correct !== true || row.reason !== null ||
      !nonnegative(row.wallMs) || row.wallMs === 0) errors.push("success");
  } else {
    if (!["operation", "correctness", "memory", "environment"]
      .includes(String(row.reason))) errors.push("reason");
    if (row.correct !== null && typeof row.correct !== "boolean") {
      errors.push("correct");
    }
    if (row.wallMs !== null && !nonnegative(row.wallMs)) errors.push("wallMs");
  }
  if (!Array.isArray(row.reports)) return [...errors, "reports"];
  if (row.reports.length > plan.measurementCount ||
    (success && row.reports.length !== plan.measurementCount)) {
    errors.push("reports.count");
  }
  for (const report of row.reports) {
    if (!object(report) || !object(report.measurement)) {
      errors.push("measurement.schema");
      continue;
    }
    const m = report.measurement;
    if (typeof m.runID !== "string" || !/^[a-f0-9-]{36}$/.test(m.runID) ||
      measurementIDs.has(m.runID)) errors.push("measurement.id");
    else measurementIDs.add(m.runID);
    if (m.schemaVersion !== 1 || m.sourceRevision !== plan.sourceRevision ||
      m.inputDigest !== plan.inputDigest ||
      m.settingsDigest !== plan.settingsDigest || m.mode !== plan.mode ||
      typeof m.instanceKey !== "string" ||
      !/^[a-f0-9]{24}$/.test(m.instanceKey) ||
      typeof m.startedAt !== "string" ||
      !Number.isFinite(Date.parse(m.startedAt))) {
      errors.push("measurement.identity");
    }
    if (!nonnegative(m.durationMs) || !nonnegative(row.wallMs) ||
      m.durationMs > row.wallMs || typeof m.complete !== "boolean" ||
      !["returned", "threw"].includes(String(m.operationOutcome))) {
      errors.push("measurement.time-or-outcome");
    }
    if (success && (m.complete !== true || m.operationOutcome !== "returned")) {
      errors.push("measurement.incomplete");
    }
    if (!object(m.stages)) errors.push("stages.schema");
    else {
      for (const stage of STAGES) {
        const s = m.stages[stage];
        if (!object(s) || !count(s.started) || !count(s.succeeded) ||
          !count(s.failed) || !count(s.active) || !count(s.peakActive) ||
          !count(s.receivedBytes) || !count(s.submittedBytes) ||
          !count(s.completedBytes) || !nonnegative(s.totalMs) ||
          !nonnegative(s.maxMs) || s.maxMs > s.totalMs ||
          s.started !== s.succeeded + s.failed + s.active ||
          s.peakActive > s.started || s.peakActive < s.active ||
          (s.started > 0 && s.peakActive === 0) ||
          (m.complete === true && s.active !== 0)) {
          errors.push(`stage.${stage}`);
        }
      }
    }
    const r = report.resources;
    if (!object(r) || !count(r.samples) || r.samples === 0 ||
      !count(r.samplingErrors) || (success && r.samplingErrors !== 0) ||
      !count(r.missedTicks) || !count(r.missingContainerSamples) ||
      r.missingContainerSamples > r.samples ||
      !nonnegative(r.maxSampleGapMs) ||
      typeof r.containerMemoryAvailable !== "boolean") {
      errors.push("resources.invalid");
    }
    if (object(r)) {
      for (const key of ["cpuUserMicros", "cpuSystemMicros", "maxRSSBytes",
        "maxHeapUsedBytes", "maxExternalBytes", "maxArrayBufferBytes",
        "maxSharpQueue", "maxSharpProcess", "sharpConcurrency"]) {
        if (!count(r[key])) errors.push(`resources.${key}`);
      }
      if (!nonnegative(r.eventLoopMaxMs) ||
        (r.eventLoopMeanMs !== null && !nonnegative(r.eventLoopMeanMs)) ||
        !nonnegative(r.sampleIntervalMs) || r.sampleIntervalMs === 0 ||
        (r.maxContainerRatio !== null && !nonnegative(r.maxContainerRatio)) ||
        (r.containerMemoryAvailable === true &&
          (r.missingContainerSamples !== 0 || r.samplingErrors !== 0 ||
            r.maxContainerRatio === null))) errors.push("resources.values");
    }
  }
  return errors;
}

export function median(values: number[]): number {
  if (values.length === 0 || values.some((v) => !nonnegative(v))) {
    throw new Error("유효한 비음수 표본이 필요합니다.");
  }
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] :
    sorted[middle - 1] / 2 + sorted[middle] / 2;
}
