import {isDeepStrictEqual} from "node:util";
import {makeComparisonPlan, makeTransformSweepPlan,
  makeTransformConfirmationPlan, type ComparisonPlan}
  from "./comparison.js";
import {validateContainerPayload} from "./container-runner.js";
import {median, type RunResult} from "./result.js";

type Row = Record<string, unknown>;
function object(value: unknown): value is Row {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function summarizeComparisons(plans: ComparisonPlan[], rows: unknown[]) {
  const issues: string[] = [];
  const sweep = !!plans[0] && Object.hasOwn(plans[0], "transformLimit");
  const confirmation = !!plans[0] && Object.hasOwn(plans[0], "experiment");
  const makePlan = confirmation ? makeTransformConfirmationPlan :
    sweep ? makeTransformSweepPlan : makeComparisonPlan;
  const repeats = confirmation ? 5 : 3;
  if (!plans[0] || !isDeepStrictEqual(plans, makePlan(plans[0]))) {
    issues.push("plan.not-complete-matrix");
  }
  const expected = new Map(plans.map((plan) => [plan.id, plan]));
  const seen = new Set<string>();
  const images = new Set<string>();
  const counts = {succeeded: 0, failed: 0, aborted: 0, unavailable: 0};
  const groups = new Map<string, {arm: string; load: string;
    transformLimit?: number | null; times: number[]; failed: number}>();
  for (const value of rows) {
    if (!object(value) || typeof value.id !== "string" ||
      !expected.has(value.id) || seen.has(value.id)) {
      issues.push("result.unknown-or-duplicate");
      continue;
    }
    seen.add(value.id);
    const plan = expected.get(value.id);
    if (!plan) continue;
    if (typeof value.imageID !== "string" ||
      !/^sha256:[a-f0-9]{64}$/.test(value.imageID)) {
      issues.push("result.image");
    } else images.add(value.imageID);
    const verdict = value.verdict;
    if (typeof verdict !== "string" || !Object.hasOwn(counts, verdict)) {
      issues.push("result.verdict");
      continue;
    }
    counts[verdict as keyof typeof counts]++;
    const variant = sweep ? {transformLimit: plan.transformLimit ?? null} : {};
    const key = `${plan.arm}-${plan.load}-${JSON.stringify(variant)}`;
    const group = groups.get(key) ??
      {arm: plan.arm, load: plan.load, ...variant, times: [], failed: 0};
    groups.set(key, group);
    if (verdict !== "succeeded") {
      group.failed++;
      continue;
    }
    if (!validateContainerPayload(plan, value.payload) ||
      !object(value.evidence) || value.evidence.OOMKilled !== false ||
      value.evidence.ExitCode !== 0 || value.evidence.Status !== "exited" ||
      value.evidence.Running !== false) {
      issues.push("result.false-success");
      continue;
    }
    const payload = value.payload as {results: RunResult[]};
    group.times.push(payload.results.reduce((sum, row) =>
      sum + (row.wallMs ?? 0), 0));
  }
  if (seen.size !== expected.size) issues.push("result.missing");
  if (images.size !== 1) issues.push("result.mixed-or-missing-image");
  return {valid: issues.length === 0, issues, planned: plans.length,
    recorded: seen.size, counts,
    comparisons: issues.length ? [] : [...groups.values()].map((group) => ({
      arm: group.arm, load: group.load,
      ...(sweep ? {transformLimit: group.transformLimit} : {}),
      successes: group.times.length, failures: group.failed,
      medianMs: group.times.length === repeats && group.failed === 0 ?
        median(group.times) : null,
    })),
    scope: confirmation ? "c-transform-five-pair-local-confirmation" :
      sweep ? "c-transform-sweep-three-repeat-not-adoption" :
        "three-repeat-exploration-not-adoption-or-five-pair-regression"};
}

export function repeatedRegression(baseline: number[], candidate: number[]) {
  if (baseline.length !== 5 || candidate.length !== 5 ||
    [...baseline, ...candidate].some((value) =>
      !Number.isFinite(value) || value <= 0)) {
    throw new Error("같은 조건으로 짝지은 유효한 다섯 회차가 필요합니다.");
  }
  const slowerPairs = candidate.filter((value, index) =>
    value * 10 >= baseline[index] * 11).length;
  const baselineMedian = median(baseline);
  const candidateMedian = median(candidate);
  return {slowerPairs, baselineMedian, candidateMedian,
    withholdAdoption: slowerPairs >= 3 &&
      candidateMedian * 10 >= baselineMedian * 11};
}
