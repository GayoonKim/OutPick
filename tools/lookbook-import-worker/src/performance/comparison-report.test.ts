import assert from "node:assert/strict";
import test from "node:test";
import {makeComparisonPlan, runComparison} from "./comparison.js";
import {repeatedRegression, summarizeComparisons} from "./comparison-report.js";

const plans = makeComparisonPlan({sourceRevision: "a".repeat(40),
  sourceDigest: "b".repeat(64), inputDigest: "c".repeat(64)});
const rows = plans.map((plan) => ({id: plan.id,
  imageID: `sha256:${"d".repeat(64)}`, verdict: "aborted"}));

test("54회 집계는 중단 실패도 원래 분모에 남기고 성공 중앙값을 만들지 않는다",
  () => {
    const report = summarizeComparisons(plans, rows);
    assert.equal(report.valid, true);
    assert.equal(report.counts.aborted, 54);
    assert.equal(report.comparisons.length, 18);
    assert.ok(report.comparisons.every((value) => value.medianMs === null));
  });

test("54회 집계는 누락 중복 이미지 변경과 거짓 성공을 차단한다", () => {
  for (const changed of [rows.slice(1), [...rows, rows[0]],
    [{...rows[0], imageID: `sha256:${"e".repeat(64)}`}, ...rows.slice(1)],
    [{...rows[0], verdict: "succeeded"}, ...rows.slice(1)]]) {
    const report = summarizeComparisons(plans, changed);
    assert.equal(report.valid, false);
    assert.deepEqual(report.comparisons, []);
  }
  assert.equal(summarizeComparisons(plans.slice(1), rows.slice(1)).valid,
    false);
});

test("54회 집계는 세 회차 모두 성공한 조합만 중앙값을 계산한다", async () => {
  const records: unknown[] = [];
  for (const plan of plans) {
    if (plan.arm !== "A" || plan.load !== "single") {
      records.push({...rows[0], id: plan.id});
      continue;
    }
    const payload = await runComparison(plan, async () =>
      ({status: "succeeded"}), {maxSampleGapMs: 500,
      readMemory: async () => ({source: "cgroup-v2", usedBytes: 1,
        limitBytes: 2 * 2**30})});
    payload.results.forEach((row) => {
      row.wallMs = plan.repeat * 10000;
    });
    records.push({...rows[0], id: plan.id, verdict: "succeeded", payload,
      evidence: {OOMKilled: false, ExitCode: 0,
        Status: "exited", Running: false}});
  }
  const report = summarizeComparisons(plans, records);
  assert.equal(report.valid, true);
  assert.equal(report.counts.succeeded, 3);
  assert.equal(report.counts.aborted, 51);
  assert.deepEqual(report.comparisons.find((x) => x.arm === "A" &&
    x.load === "single"), {arm: "A", load: "single", successes: 3,
    failures: 0, medianMs: 40000});
});

test("반복 악화는 다섯 쌍 중 세 번과 중앙값 모두 10퍼센트일 때 보류한다", () => {
  assert.equal(repeatedRegression([100, 100, 100, 100, 100],
    [110, 110, 110, 99, 99]).withholdAdoption, true);
  assert.equal(repeatedRegression([100, 100, 100, 100, 100],
    [110, 110, 109, 99, 99]).withholdAdoption, false);
  assert.equal(repeatedRegression([10, 20, 100, 200, 300],
    [11, 22, 90, 220, 250]).withholdAdoption, false);
  assert.throws(() => repeatedRegression([1, 2, 3], [1, 2, 3]));
  assert.throws(() => repeatedRegression([0, 1, 2, 3, 4], [1, 2, 3, 4, 5]));
});
