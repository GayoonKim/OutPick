import {createHash} from "node:crypto";
import {performance} from "node:perf_hooks";
import {isDeepStrictEqual} from "node:util";
import {PipelineRuntime} from "../pipeline/resources.js";
import {BufferInventory} from "./buffer-inventory.js";
import {superviseMemory} from "./memory-supervisor.js";
import {runSeasons, type SeasonAttemptOutcome} from "./season-runner.js";
import {withMeasurement} from "./session.js";
import {type PlannedRun, type RunResult, validateResultSet} from "./result.js";

export const ARMS = ["A", "B", "C", "D", "E", "F"] as const;
export type Arm = typeof ARMS[number];
export type ComparisonSeason = {id: string; brandID: string; seasonID: string};
const all = {kind: "refill" as const, concurrency: null};
const noLimits = {download: null, transform: null, upload: null, paths: null};

export function comparisonPolicy(arm: Arm) {
  if (!ARMS.includes(arm)) throw new Error("알 수 없는 비교 구조입니다.");
  const batch = arm === "B" || arm === "D";
  const staged = arm === "C" || arm === "E";
  return {
    seasons: {order: arm === "D" || arm === "E" ?
      "serial-per-brand" as const : "parallel" as const,
    concurrency: arm === "F" ? null : 6},
    pipeline: arm === "A" ? null : {
      assets: batch ?
        {kind: "batch" as const, size: 8, concurrency: null} : all,
      hashes: batch ?
        {kind: "batch" as const, size: 8, concurrency: null} : all,
      limits: staged ? {download: 4, transform: 2, upload: 4, paths: null} :
        noLimits,
    },
    baselineAssets: 3, baselineHashes: 4, reuse: "off",
  };
}

const seasonIDs = ["2026FW", "2026SS", "2025FW", "2025SS", "2024FW", "2024SS"];
export function comparisonInputs(load: "single" | "six" | "synthetic-three") {
  const ids = load === "single" ? ["2026SS"] : seasonIDs;
  if (!["single", "six", "synthetic-three"].includes(load)) {
    throw new Error("알 수 없는 비교 부하입니다.");
  }
  return ids.map((seasonID): ComparisonSeason => ({id: seasonID, seasonID,
    brandID: load === "synthetic-three" ? `synthetic-${seasonID.slice(0, 4)}` :
      "unaffected"}));
}

export type ComparisonPlan = {
  id: string; arm: Arm; repeat: number;
  load: "single" | "six" | "synthetic-three";
  sourceRevision: string; sourceDigest: string; inputDigest: string;
  settingsDigest: string;
  transformLimit?: 1 | 2 | 4 | null;
  experiment?: "transform-confirmation-v1";
};
export function makeComparisonPlan(source: {
  sourceRevision: string; sourceDigest: string; inputDigest: string;
}): ComparisonPlan[] {
  if (!/^[a-f0-9]{7,64}$/.test(source.sourceRevision) ||
    ![source.sourceDigest, source.inputDigest]
      .every((value) => /^[a-f0-9]{64}$/.test(value))) {
    throw new Error("코드와 입력 식별자가 필요합니다.");
  }
  const loads = ["single", "six", "synthetic-three"] as const;
  const plans: ComparisonPlan[] = [];
  for (let repeat = 1; repeat <= 3; repeat++) {
    for (let offset = 0; offset < 3; offset++) {
      const load = loads[(offset + repeat - 1) % 3];
      for (let index = 0; index < 6; index++) {
        const arm = ARMS[(index + repeat - 1 + offset * 2) % 6];
        const settings = {arm, load, policy: comparisonPolicy(arm),
          inputs: comparisonInputs(load), maxSampleGapMs: 500,
          resourceLimits: {cpus: 1, memoryBytes: 2 * 2**30, swapBytes: 0},
          runtime: "pinned-linux-arm64-node24-image",
          phaseOrder: ["extraction-to-review", "post-approval-assets"]};
        plans.push({sourceRevision: source.sourceRevision,
          sourceDigest: source.sourceDigest, inputDigest: source.inputDigest,
          id: `${arm}-${load}-${repeat}`, arm, repeat, load,
          settingsDigest: createHash("sha256").update(JSON.stringify(settings))
            .digest("hex")});
      }
    }
  }
  return plans;
}

export function validateComparisonPlan(plan: ComparisonPlan): void {
  const makePlan = Object.hasOwn(plan, "experiment") ?
    makeTransformConfirmationPlan : Object.hasOwn(plan, "transformLimit") ?
      makeTransformSweepPlan : makeComparisonPlan;
  const expected = makePlan(plan).find((entry) => entry.id === plan.id);
  if (!isDeepStrictEqual(plan, expected)) {
    throw new Error("승인된 구조 비교 계획과 일치하지 않습니다.");
  }
}

export function makeTransformConfirmationPlan(source: Parameters<
  typeof makeComparisonPlan>[0]): ComparisonPlan[] {
  const baselines = makeComparisonPlan(source).filter((plan) =>
    plan.arm === "C" && plan.repeat === 1);
  const loads = ["single", "six", "synthetic-three"] as const;
  const plans: ComparisonPlan[] = [];
  for (let repeat = 1; repeat <= 5; repeat++) {
    for (let offset = 0; offset < loads.length; offset++) {
      const loadIndex = (offset + repeat - 1) % loads.length;
      const load = loads[loadIndex];
      const base = baselines.find((plan) => plan.load === load);
      if (!base) throw new Error("C 기준 설정이 없습니다.");
      const limits = (repeat + loadIndex) % 2 === 1 ? [2, 1] : [1, 2];
      for (const value of limits) {
        const transformLimit = value as 1 | 2;
        const experiment = "transform-confirmation-v1" as const;
        plans.push({...base, repeat, transformLimit, experiment,
          id: `C-confirm-${load}-t${transformLimit}-pair-${repeat}`,
          settingsDigest: createHash("sha256").update(JSON.stringify({
            experiment, baseSettingsDigest: base.settingsDigest, transformLimit,
          })).digest("hex")});
      }
    }
  }
  return plans;
}

// 구조 탐색과 별도 식별자로 변환 한 축만 비교한다. 기존 54회 정책은 유지한다.
export function makeTransformSweepPlan(source: Parameters<
  typeof makeComparisonPlan>[0]): ComparisonPlan[] {
  const baselines = makeComparisonPlan(source).filter((plan) =>
    plan.arm === "C" && plan.load === "six");
  const limits = [1, 2, 4, null] as const;
  return baselines.flatMap((base) => limits.map((_, index) => {
    const transformLimit = limits[(index + base.repeat - 1) % limits.length];
    return {...base, transformLimit,
      id: `C-transform-${transformLimit ?? "all"}-${base.repeat}`,
      settingsDigest: createHash("sha256").update(JSON.stringify({
        experiment: "c-transform-sweep-v1",
        baseSettingsDigest: base.settingsDigest, transformLimit,
      })).digest("hex")};
  }));
}

export function phasePlans(plan: ComparisonPlan,
  measurementEnabled = true): PlannedRun[] {
  return (["local-extraction", "local-assets"] as const).map((mode) => ({
    ...plan, id: `${plan.id}-${mode}`, mode,
    measurementCount: measurementEnabled ? 1 : 0,
    settingsDigest: measurementEnabled ? plan.settingsDigest :
      createHash("sha256").update(`${plan.settingsDigest}:measurement-off`)
        .digest("hex"),
  }));
}

export async function runComparison(
  plan: ComparisonPlan,
  execute: (phase: "local-extraction" | "local-assets",
    season: ComparisonSeason, context: {attempt: number; signal: AbortSignal;
      pipeline: PipelineRuntime | undefined}) => Promise<SeasonAttemptOutcome>,
  memoryOptions?: Parameters<typeof superviseMemory>[1],
  measurementEnabled = true,
) {
  validateComparisonPlan(plan);
  const expected = phasePlans(plan, measurementEnabled);
  const results: RunResult[] = [];
  const details: unknown[] = [];
  const policy = comparisonPolicy(plan.arm);
  if (Object.hasOwn(plan, "transformLimit") && policy.pipeline) {
    policy.pipeline.limits.transform = plan.transformLimit ?? null;
  }
  const outcome = await superviseMemory(async (signal) => {
    for (const entry of expected) {
      if (signal.aborted) break;
      // 검토 종료와 승인 후 저장의 scope/공용 runtime을 분리한다.
      const pipeline = policy.pipeline ?
        new PipelineRuntime({...policy.pipeline, signal}) : undefined;
      const buffers = new BufferInventory();
      const reports: unknown[] = [];
      const started = performance.now();
      const work = () => withMeasurement({
        enabled: measurementEnabled, ...entry, instanceID: plan.id,
        emit: (report) => reports.push(report),
      }, entry.mode, () => runSeasons(comparisonInputs(plan.load),
        policy.seasons, (season, context) => execute(
          entry.mode as "local-extraction" | "local-assets", season,
          {...context, pipeline}), {signal}));
      const records = await (measurementEnabled ? buffers.run(work) : work());
      const inventory = buffers.snapshot();
      const success = records.every((record) =>
        record.status === "succeeded" || (entry.mode === "local-extraction" &&
          record.status === "needs-review")) && inventory.objects === 0;
      results.push({...entry, reports, wallMs: performance.now() - started,
        outcome: signal.aborted ? "aborted" : success ? "succeeded" : "failed",
        reason: signal.aborted ? "environment" : success ? null : "operation",
        correct: success ? true : null});
      const firstEnded = records[0].attempts.at(-1)?.endedMs;
      details.push({phase: entry.mode, seasons: records, buffers: inventory,
        slots: pipeline?.snapshot() ?? null,
        firstSeasonMs: firstEnded === undefined ? null : firstEnded - started});
      if (!success) break;
    }
  }, memoryOptions ?? {maxSampleGapMs: 500});
  // 중단 직전 정상 완료된 구간도 전체 실험의 성공으로 재사용하지 않는다.
  if (outcome.status !== "completed") {
    const reason = outcome.memory.stop?.reason ?? "operation";
    for (const row of results) {
      row.outcome = outcome.status === "unavailable" ? "unavailable" :
        outcome.status === "stopped" ? "aborted" : "failed";
      row.reason = reason;
    }
  }
  for (const entry of expected) {
    if (results.some((row) => row.id === entry.id)) continue;
    results.push({...entry, outcome: outcome.status === "unavailable" ?
      "unavailable" : "aborted", reason: outcome.memory.stop?.reason ??
      "operation", correct: null, wallMs: null, reports: []});
  }
  const validation = validateResultSet(expected, results);
  return {id: plan.id, measurementEnabled,
    results, details, memory: outcome.memory, validation};
}
