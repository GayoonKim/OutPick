import {isDeepStrictEqual} from "node:util";
import {comparisonInputs, makeTransformConfirmationPlan,
  type ComparisonPlan} from "./comparison.js";
import {repeatedRegression, summarizeComparisons}
  from "./comparison-report.js";

type Row = Record<string, unknown>;
function object(value: unknown): value is Row {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function summarizeTransformConfirmation(
  plans: ComparisonPlan[], rows: unknown[],
) {
  const summary = summarizeComparisons(plans, rows);
  const issues = [...summary.issues];
  if (!plans[0] || !isDeepStrictEqual(plans,
    makeTransformConfirmationPlan(plans[0]))) {
    issues.push("confirmation.plan");
  }
  const expected = new Map(plans.map((plan) => [plan.id, plan]));
  const metrics = new Map<string, {totalMs: number; firstAssetMs: number}>();
  if (issues.length === 0) {
    for (const row of rows) {
      if (!object(row) || row.verdict !== "succeeded") continue;
      const plan = expected.get(String(row.id));
      const payload = row.payload;
      if (!plan || !object(payload) || !Array.isArray(payload.results) ||
        !Array.isArray(payload.details) || payload.details.length !== 2) {
        issues.push("confirmation.details");
        continue;
      }
      const detail = payload.details[1];
      const asset = payload.results[1];
      if (!object(detail) || detail.phase !== "local-assets" ||
        !Array.isArray(detail.seasons) || !object(detail.seasons[0]) ||
        detail.seasons[0].id !== comparisonInputs(plan.load)[0].id ||
        !object(asset) || asset.mode !== "local-assets" ||
        typeof detail.firstSeasonMs !== "number" ||
        !Number.isFinite(detail.firstSeasonMs) || detail.firstSeasonMs <= 0 ||
        detail.firstSeasonMs > Number(asset.wallMs)) {
        issues.push("confirmation.first-season");
        continue;
      }
      metrics.set(plan.id, {firstAssetMs: detail.firstSeasonMs,
        totalMs: payload.results.reduce((sum: number, item: Row) =>
          sum + Number(item.wallMs), 0)});
    }
  }
  const loads = issues.length ? [] :
    (["single", "six", "synthetic-three"] as const).map((load) => {
      const pairs = Array.from({length: 5}, (_, index) => {
        const repeat = index + 1;
        const find = (limit: number) => plans.find((plan) =>
          plan.load === load && plan.repeat === repeat &&
          plan.transformLimit === limit);
        return {repeat, baseline: metrics.get(find(2)?.id ?? "") ?? null,
          candidate: metrics.get(find(1)?.id ?? "") ?? null};
      });
      const complete = pairs.every((pair) => pair.baseline && pair.candidate);
      const regression = (key: "totalMs" | "firstAssetMs") => complete ?
        repeatedRegression(pairs.map((p) => p.baseline?.[key] ?? 0),
          pairs.map((p) => p.candidate?.[key] ?? 0)) : null;
      const total = regression("totalMs");
      const firstAsset = regression("firstAssetMs");
      return {load, complete, pairs, total, firstAsset,
        // 표본 부족은 악화 없음으로 바꾸지 않는다.
        withholdCandidate: !complete || total?.withholdAdoption === true ||
          firstAsset?.withholdAdoption === true};
    });
  return {valid: issues.length === 0, issues, summary, loads,
    withholdCandidate: issues.length > 0 ||
      loads.some((load) => load.withholdCandidate),
    scope: "candidate-transform-1-vs-baseline-2-local-only"};
}
