import assert from "node:assert/strict";
import {isDeepStrictEqual} from "node:util";
import {comparisonInputs} from "./comparison.js";
import {largeSeasons, LARGE_INPUT_DIGEST, metadataDigest}
  from "./large-input.js";
import {PRESSURE_INPUT} from "./reuse-contract.js";
import {submissionPolicy} from "./submission-comparison.js";
import type {ReusePlan} from "./reuse-comparison.js";
import type {PlannedRun} from "./result.js";

export type BrandLoad = "standard" | "large";
export type BrandOrder = "parallel" | "serial-brands";
export function brandInputs(load: BrandLoad) {
  assert.ok(["standard", "large"].includes(load));
  return load === "standard" ? comparisonInputs("synthetic-three") :
    largeSeasons().map((season, index) => ({...season,
      brandID: `synthetic-large-brand-${Math.floor(index / 2) + 1}`}));
}
export function brandInputDigest(load: BrandLoad): string {
  return metadataDigest({base: load === "large" ? LARGE_INPUT_DIGEST :
    PRESSURE_INPUT, mapping: brandInputs(load), version: "brand-input-v1"});
}
export function makeBrandPlan(source: Pick<PlannedRun,
  "sourceRevision" | "sourceDigest">): ReusePlan[] {
  assert.match(source.sourceRevision, /^[a-f0-9]{7,64}$/);
  assert.match(source.sourceDigest, /^[a-f0-9]{64}$/);
  const plans: ReusePlan[] = [];
  for (let repeat = 1; repeat <= 5; repeat++) {
    const loads: BrandLoad[] = repeat % 2 ? ["standard", "large"] :
      ["large", "standard"];
    for (const load of loads) {
      const parallelFirst = (load === "standard") === (repeat % 2 === 1);
      const orders: BrandOrder[] = parallelFirst ?
        ["parallel", "serial-brands"] : ["serial-brands", "parallel"];
      for (const brandOrder of orders) {
        const setting = {brandComparison: "brand-fifo-v1" as const,
          brandLoad: load, brandOrder, budget: "128" as const,
          submission: "submission-v1" as const, submissionArm: "P4" as const,
          arm: "prepared" as const, diagnostic: "asset-timeline-v1" as const,
          load: "synthetic-three" as const,
          ...(load === "large" ? {largeInput: "large-input-v1" as const} : {})};
        const inputDigest = brandInputDigest(load);
        plans.push({sourceRevision: source.sourceRevision,
          sourceDigest: source.sourceDigest, inputDigest, ...setting,
          id: `brand-${load}-${brandOrder}-${repeat}`, repeat,
          experiment: "reuse-comparison-v1", mode: "local-connected",
          measurementCount: 1, settingsDigest: metadataDigest({
            ...setting, policy: submissionPolicy("128", "P4"),
            inputs: brandInputs(load), concurrency: 6, attempts: 5,
            inputDigest, progressLimitBytes: 256 * 1024})});
      }
    }
  }
  return plans;
}
export function validateBrandPlan(plan: ReusePlan): void {
  assert.ok(isDeepStrictEqual(plan, makeBrandPlan(plan)
    .find((expected) => expected.id === plan.id)));
}
