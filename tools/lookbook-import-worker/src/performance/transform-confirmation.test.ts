import assert from "node:assert/strict";
import test from "node:test";
import {makeComparisonPlan, makeTransformSweepPlan,
  makeTransformConfirmationPlan, runComparison, validateComparisonPlan}
  from "./comparison.js";
import {summarizeTransformConfirmation}
  from "./transform-confirmation-report.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: "c".repeat(64)};
const plans = makeTransformConfirmationPlan(source);

async function records() {
  return Promise.all(plans.map(async (plan) => {
    const payload = await runComparison(plan, async (_phase, _season, ctx) => {
      assert.equal(ctx.pipeline?.snapshot().transform.limit,
        plan.transformLimit);
      return {status: "succeeded"};
    }, {maxSampleGapMs: 500, readMemory: async () =>
      ({source: "cgroup-v2", usedBytes: 1, limitBytes: 2 * 2**30})});
    payload.results.forEach((row) => {
      row.wallMs = plan.repeat * 20000;
    });
    const detail = payload.details[1] as {firstSeasonMs: number};
    detail.firstSeasonMs = 5000;
    return {id: plan.id, verdict: "succeeded",
      imageID: `sha256:${"d".repeat(64)}`, payload,
      evidence: {OOMKilled: false, ExitCode: 0,
        Status: "exited", Running: false}};
  }));
}

test("변환 확인 30회는 부하별 다섯 쌍을 교차하고 다른 실험을 거절한다",
  () => {
    assert.equal(plans.length, 30);
    assert.equal(new Set(plans.map((p) => p.id)).size, 30);
    plans.forEach(validateComparisonPlan);
    for (let i = 0; i < plans.length; i += 2) {
      assert.equal(plans[i].load, plans[i + 1].load);
      assert.equal(plans[i].repeat, plans[i + 1].repeat);
      assert.deepEqual([plans[i].transformLimit, plans[i + 1].transformLimit]
        .sort(), [1, 2]);
    }
    for (const load of ["single", "six", "synthetic-three"]) {
      const pairs = plans.filter((p) => p.load === load);
      assert.equal(pairs.length, 10);
      for (let i = 2; i < pairs.length; i += 2) {
        assert.notEqual(pairs[i].transformLimit, pairs[i - 2].transformLimit);
      }
    }
    for (const change of [{transformLimit: 4}, {repeat: 6}, {arm: "E"},
      {experiment: undefined}, {experiment: "unknown"}, {download: 8}]) {
      assert.throws(() => validateComparisonPlan({...plans[0], ...change} as
        typeof plans[number]));
    }
    for (const plan of [...makeComparisonPlan(source),
      ...makeTransformSweepPlan(source)]) validateComparisonPlan(plan);
  });

test("다섯 쌍 판정은 결과 순서와 무관하게 첫 시즌 악화를 별도로 보류한다",
  async () => {
    const rows = await records();
    for (const [index, plan] of plans.entries()) {
      if (plan.transformLimit === 1 && plan.repeat <= 3) {
        (rows[index].payload.details[1] as {firstSeasonMs: number})
          .firstSeasonMs = 5500;
      }
    }
    const result = summarizeTransformConfirmation(plans, rows);
    assert.equal(result.valid, true);
    assert.equal(result.summary.counts.succeeded, 30);
    assert.equal(result.summary.comparisons.length, 6);
    assert.ok(result.summary.comparisons.every((g) => g.medianMs === 120000));
    assert.equal(result.withholdCandidate, true);
    assert.ok(result.loads.every((load) => load.complete &&
      load.total?.withholdAdoption === false &&
      load.firstAsset?.slowerPairs === 3 &&
      load.firstAsset.withholdAdoption === true));
    assert.deepEqual(summarizeTransformConfirmation(plans, [...rows].reverse())
      .loads, result.loads);
  });

test("다섯 쌍 판정은 중단 누락 잘못된 첫 시즌과 이전 표본 혼입을 숨기지 않는다",
  async () => {
    const rows = await records();
    assert.equal(summarizeTransformConfirmation(plans, rows)
      .withholdCandidate, false);
    const stopped = rows.map((row, i) => i === 0 ?
      {...row, verdict: "aborted"} : row);
    const incomplete = summarizeTransformConfirmation(plans, stopped);
    assert.equal(incomplete.valid, true);
    assert.equal(incomplete.summary.counts.aborted, 1);
    assert.equal(incomplete.withholdCandidate, true);
    assert.equal(incomplete.loads[0].total, null);
    for (const badRows of [rows.slice(1), [...rows, rows[0]],
      rows.map((row, i) => i === 0 ? {...row, id: "C-transform-1-1"} : row)]) {
      assert.equal(summarizeTransformConfirmation(plans, badRows).valid, false);
    }
    for (const firstSeasonMs of [NaN, null, -1, 999999]) {
      const invalid = structuredClone(rows);
      (invalid[0].payload.details[1] as {firstSeasonMs: unknown})
        .firstSeasonMs = firstSeasonMs;
      assert.equal(summarizeTransformConfirmation(plans, invalid).valid, false);
    }
    assert.equal(summarizeTransformConfirmation(makeTransformSweepPlan(source),
      rows).valid, false);
  });
