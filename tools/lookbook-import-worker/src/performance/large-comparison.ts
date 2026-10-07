import assert from "node:assert/strict";
import {isDeepStrictEqual} from "node:util";
import {makeReusePlan, validateReusePayload, type ReusePlan}
  from "./reuse-comparison.js";
import {largeSeasons, LARGE_INPUT_DIGEST, metadataDigest}
  from "./large-input.js";
import {submissionPolicy} from "./submission-comparison.js";
import {validateResultSet} from "./result.js";
import {largeStatistics, type LargeSample} from "./large-statistics.js";

export function makeLargePlan(source: Parameters<typeof makeReusePlan>[0]):
  ReusePlan[] {
  assert.equal(source.inputDigest, LARGE_INPUT_DIGEST);
  const base = makeReusePlan(source)[0];
  const settings = [["U", "off"], ["P4", "128"], ["U", "128"],
    ["U", "256"], ["P4", "256"], ["P4", "512"], ["U", "512"]] as const;
  return settings.map(([submissionArm, budget]) => {
    const setting = {largeInput: "large-input-v1" as const,
      diagnostic: "asset-timeline-v1" as const, submissionArm, budget,
      arm: budget === "off" ? "off" as const : "prepared" as const};
    return {...base, ...setting, id: `large-${submissionArm}-${budget}-1`,
      repeat: 1, settingsDigest: metadataDigest({...setting,
        policy: submissionPolicy(budget, submissionArm),
        seasons: largeSeasons(), concurrency: 6,
        inputDigest: LARGE_INPUT_DIGEST, attempts: 5})};
  });
}

// 커버 선준비와 P4를 유지하고 해시 원본 보관만 끄는 독립 준비 대조군이다.
export function makeLargeControlPlan(
  source: Parameters<typeof makeReusePlan>[0]): ReusePlan[] {
  const base = makeLargePlan(source)[0];
  const setting = {largeInput: "large-input-v1" as const,
    largeControl: "p4-off-prepared-v1" as const,
    diagnostic: "asset-timeline-v1" as const, submissionArm: "P4" as const,
    budget: "off" as const, arm: "prepared" as const};
  return [{...base, ...setting, id: "large-control-P4-off-1", repeat: 1,
    settingsDigest: metadataDigest({...setting,
      policy: submissionPolicy("off", "P4"), seasons: largeSeasons(),
      concurrency: 6, inputDigest: LARGE_INPUT_DIGEST, attempts: 5})}];
}

export function makeLargeConfirmationPlan(
  source: Parameters<typeof makeReusePlan>[0]): ReusePlan[] {
  const base = makeLargePlan(source)[0];
  const orders = [["off", "128", "256"], ["128", "256", "off"],
    ["256", "off", "128"], ["off", "256", "128"],
    ["128", "off", "256"]] as const;
  return orders.flatMap((order, index) => order.map((budget) => {
    const setting = {largeInput: "large-input-v1" as const,
      largeConfirmation: "p4-reuse-five-pair-v1" as const,
      diagnostic: "asset-timeline-v1" as const, submissionArm: "P4" as const,
      budget, arm: "prepared" as const};
    return {...base, ...setting, id: `large-confirm-P4-${budget}-${index+1}`,
      repeat: index + 1, settingsDigest: metadataDigest({...setting,
        policy: submissionPolicy(budget, "P4"), seasons: largeSeasons(),
        concurrency: 6, inputDigest: LARGE_INPUT_DIGEST, attempts: 5})};
  }));
}

type Row = {id: string; imageID: string; verdict: string; reason: string;
  cleanupPending?: boolean;
  evidence: {Status: string; Running: boolean; OOMKilled: boolean;
    ExitCode: number} | null;
  payload: ReturnType<typeof JSON.parse>};

export function pressureEstablished(cache: {rejectedByBudget: number;
  misses: number} | null): boolean {
  return !!cache && cache.rejectedByBudget > 0 && cache.misses > 0;
}

// 준비 측정과 다섯 쌍 확인을 분리하며 각 계획의 실패/미수행 분모를 보존한다.
export function summarizeLarge(plans: ReusePlan[], rows: Row[]) {
  const issues: string[] = [];
  const control = !!plans[0] && Object.hasOwn(plans[0], "largeControl");
  const confirmation = !!plans[0] &&
    Object.hasOwn(plans[0], "largeConfirmation");
  const make = confirmation ? makeLargeConfirmationPlan :
    control ? makeLargeControlPlan : makeLargePlan;
  if (!plans[0] || !isDeepStrictEqual(plans, make(plans[0]))) {
    issues.push("plan.matrix");
  }
  const seen = new Set<string>();
  const images = new Set<string>();
  const measurementIDs = new Set<string>();
  const counts = {succeeded: 0, aborted: 0, failed: 0, unavailable: 0,
    notRun: 0};
  const conditions = [];
  const samples: LargeSample[] = [];
  let halt = false;
  for (const row of rows) {
    const plan = plans.find((p) => p.id === row.id);
    if (!plan || seen.has(row.id)) {
      issues.push("result.unknown-or-duplicate");
      continue;
    }
    if (row.id !== plans[seen.size]?.id) issues.push("result.order");
    seen.add(row.id);
    if (!/^sha256:[a-f0-9]{64}$/.test(row.imageID)) {
      issues.push("result.image");
    } else images.add(row.imageID);
    if (!Object.hasOwn(counts, row.verdict)) {
      issues.push("result.verdict");
      continue;
    }
    counts[row.verdict as keyof typeof counts]++;
    let validSuccess = false;
    if (row.verdict === "notRun") {
      if (!halt || row.payload !== null || row.evidence !== null ||
        row.reason !== "prior-condition-halted") issues.push("result.not-run");
    } else {
      if (halt) issues.push("result.started-after-halt");
      const exited = row.evidence?.Status === "exited" &&
        row.evidence.Running === false;
      if (row.payload && (!Array.isArray(row.payload.results) ||
        !validateResultSet([plan], row.payload.results).valid)) {
        issues.push("result.partial-mismatch");
      }
      validSuccess = row.verdict === "succeeded" && exited &&
        row.evidence?.OOMKilled === false && row.evidence.ExitCode === 0 &&
        validateReusePayload(plan, row.payload);
      if (row.verdict === "succeeded" && !validSuccess) {
        issues.push("result.false-success");
      }
      if (confirmation && validSuccess) {
        const measurementID = row.payload.results[0].reports[0]
          .measurement.runID;
        if (measurementIDs.has(measurementID)) {
          issues.push("result.reused-measurement");
        }
        measurementIDs.add(measurementID);
      }
      if (row.verdict === "aborted" && row.reason === "memory") {
        const stop = row.payload?.memory?.stop;
        if (!exited || !(row.evidence?.OOMKilled ||
          stop?.reason === "memory" && stop.detail === "sustained-high")) {
          issues.push("result.false-memory-abort");
        }
      } else if (row.verdict !== "succeeded") halt = true;
    }
    const cache = row.payload?.cache;
    if (row.cleanupPending) halt = true;
    conditions.push({id: plan.id, arm: plan.submissionArm,
      budget: plan.budget, verdict: row.verdict,
      pressureEstablished: validSuccess ?
        pressureEstablished(cache) : null,
      wallMs: validSuccess ? row.payload.results[0].wallMs :
        null, memoryMaxRatio: row.payload?.memory?.maxRatio ?? null});
    if (confirmation) {
      const succeeded = validSuccess;
      samples.push({budget: plan.budget, repeat: plan.repeat,
        verdict: row.verdict,
        wallMs: succeeded ? row.payload.results[0].wallMs : null,
        firstMs: succeeded ? row.payload.detail.firstSeasonMs : null,
        seasonMs: succeeded ? Object.fromEntries(row.payload.detail
          .seasonCompletedMs.map((s: {id: string; elapsedMs: number}) =>
            [s.id, s.elapsedMs])) : {},
        readBytes: succeeded ? row.payload.results[0].reports[0]
          .measurement.stages["image.download"].receivedBytes : null,
        memoryMaxRatio: row.payload?.memory?.maxRatio ?? null,
        pressure: succeeded ? pressureEstablished(cache) : null});
    }
  }
  if (seen.size !== plans.length) issues.push("result.missing");
  if (images.size !== 1) issues.push("result.mixed-image");
  return {valid: issues.length === 0, issues, planned: plans.length,
    recorded: seen.size, counts, conditions, regressions: [],
    ...(confirmation && !issues.length ? largeStatistics(samples) : {}),
    scope: confirmation ? "large-p4-five-pair-local-not-cloud-adoption" :
      control ? "large-p4-off-control-qualification-not-adoption" :
        "large-input-seven-qualification-not-performance-adoption"};
}
