import {isDeepStrictEqual} from "node:util";
import {makeBrandPlan} from "./brand-comparison.js";
import {brandStatistics, type BrandSample} from "./brand-statistics.js";
import {validateReusePayload, type ReusePlan} from "./reuse-comparison.js";
import {validateResultSet} from "./result.js";

type Row = {id: string; imageID: string; verdict: string; reason: string;
  cleanupPending?: boolean;
  evidence: {Status: string; Running: boolean; OOMKilled: boolean;
    ExitCode: number} | null;
  payload: ReturnType<typeof JSON.parse>};

// 실패/중단도 고정 분모에 남긴다. OOM의 누락 payload를 정상으로 보충하지 않는다.
export function summarizeBrand(plans: ReusePlan[], rows: Row[]) {
  const issues: string[] = [];
  if (!plans[0] || !isDeepStrictEqual(plans, makeBrandPlan(plans[0]))) {
    issues.push("plan.matrix");
  }
  const seen = new Set<string>();
  const images = new Set<string>();
  const measurements = new Set<string>();
  const counts = {succeeded: 0, aborted: 0, failed: 0,
    unavailable: 0, notRun: 0};
  const samples: BrandSample[] = [];
  let halted = false;
  for (const row of rows) {
    const plan = plans.find((p) => p.id === row.id);
    if (!plan || seen.has(row.id)) {
      issues.push("result.unknown-or-duplicate");
      continue;
    }
    if (row.id !== plans[seen.size]?.id) issues.push("result.order");
    seen.add(row.id);
    if (!/^sha256:[a-f0-9]{64}$/.test(row.imageID)) issues.push("result.image");
    else images.add(row.imageID);
    if (!Object.hasOwn(counts, row.verdict)) {
      issues.push("result.verdict");
      continue;
    }
    counts[row.verdict as keyof typeof counts]++;
    let validSuccess = false;
    if (row.verdict === "notRun") {
      if (!halted || row.payload !== null || row.evidence !== null ||
        row.reason !== "prior-condition-halted") issues.push("result.not-run");
    } else {
      if (halted) issues.push("result.started-after-halt");
      const exited = row.evidence?.Status === "exited" &&
        row.evidence.Running === false;
      if (row.payload?.results &&
        !validateResultSet([plan], row.payload.results).valid) {
        issues.push("result.partial-mismatch");
      }
      validSuccess = row.verdict === "succeeded" && exited &&
        row.evidence?.OOMKilled === false && row.evidence.ExitCode === 0 &&
        !row.cleanupPending && validateReusePayload(plan, row.payload);
      if (row.verdict === "succeeded" && !validSuccess) {
        issues.push("result.false-success");
      }
      if (validSuccess) {
        const id = row.payload.results[0].reports[0].measurement.runID;
        if (measurements.has(id)) issues.push("result.reused-measurement");
        measurements.add(id);
      }
      if (row.verdict === "aborted" && row.reason === "memory") {
        const stop = row.payload?.memory?.stop;
        if (!exited || !(row.evidence?.OOMKilled ||
          stop?.reason === "memory" && stop.detail === "sustained-high")) {
          issues.push("result.false-memory-abort");
        }
      } else if (row.verdict !== "succeeded") halted = true;
    }
    if (row.cleanupPending) halted = true;
    const detail = row.payload?.detail;
    samples.push({id: plan.id, load: plan.brandLoad!, order: plan.brandOrder!,
      repeat: plan.repeat, verdict: row.verdict,
      wallMs: validSuccess ? row.payload.results[0].wallMs : null,
      firstSeasonMs: validSuccess ? detail.firstSeasonMs : null,
      firstBrandMs: validSuccess ? detail.firstBrandMs : null,
      brands: validSuccess ? detail.brands : [],
      memoryMaxRatio: row.payload?.memory?.maxRatio ?? null,
      readBytes: validSuccess ? row.payload.results[0].reports[0]
        .measurement.stages["image.download"].receivedBytes : null});
  }
  if (seen.size !== plans.length) issues.push("result.missing");
  if (images.size !== 1) issues.push("result.mixed-image");
  return {valid: issues.length === 0, issues, planned: plans.length,
    recorded: seen.size, counts, samples,
    ...(!issues.length ? brandStatistics(samples) : {}),
    scope: "brand-fifo-local-one-instance-not-cloud-adoption"};
}
