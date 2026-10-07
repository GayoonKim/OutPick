import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {makeComparisonPlan, makeTransformSweepPlan, runComparison,
  validateComparisonPlan} from "./comparison.js";
import {summarizeComparisons} from "./comparison-report.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: "c".repeat(64)};
const plans = makeTransformSweepPlan(source);
const memory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};

test("변환 대조 12회는 한 축만 고정하고 기존 54회와 식별자를 분리한다", () => {
  assert.equal(plans.length, 12);
  assert.equal(new Set(plans.map((p) => p.id)).size, 12);
  assert.deepEqual(plans.map((p) => p.transformLimit),
    [1, 2, 4, null, 2, 4, null, 1, 4, null, 1, 2]);
  for (const plan of plans) {
    validateComparisonPlan(plan);
    assert.equal(plan.arm, "C");
    assert.equal(plan.load, "six");
  }
  const original = makeComparisonPlan(source);
  original.forEach(validateComparisonPlan);
  assert.ok(plans.every((p) => !original.some((o) =>
    o.id === p.id || o.settingsDigest === p.settingsDigest)));
  for (const change of [{arm: "E"}, {load: "single"}, {transformLimit: 8},
    {transformLimit: undefined}, {download: 8},
    {settingsDigest: original[0].settingsDigest}]) {
    assert.throws(() => validateComparisonPlan({...plans[0], ...change} as
      typeof plans[number]));
  }
});

test("변환 대조는 시즌 공용 실제 슬롯만 바꾸고 나머지 정책을 유지한다",
  async () => {
    for (const plan of plans.slice(0, 4)) {
      let active = 0;
      let peak = 0;
      const result = await runComparison(plan, async (phase, _season, ctx) => {
        const pipeline = ctx.pipeline;
        assert.ok(pipeline);
        const snapshot = pipeline.snapshot();
        assert.equal(snapshot.download.limit, 4);
        assert.equal(snapshot.upload.limit, 4);
        assert.equal(snapshot.paths.limit, null);
        assert.equal(pipeline.sourceBuffers, undefined);
        assert.deepEqual(pipeline.assets,
          {kind: "refill", concurrency: null});
        if (phase === "local-assets") {
          await Promise.all(Array.from({length: 3}, () =>
            pipeline.run("transform", async () => {
              active++;
              peak = Math.max(peak, active);
              await setImmediate();
              active--;
            })));
        }
        return {status: "succeeded"};
      }, memory);
      assert.equal(result.validation.eligibleIDs.length, 2);
      assert.equal(active, 0);
      assert.equal(peak, plan.transformLimit ?? 18);
    }
  });

test("변환 대조 집계는 제한별 세 회차를 분리하고 중단을 분모에 남긴다",
  async () => {
    const rows: Array<{id: string; imageID: string; verdict: string;
      payload: Awaited<ReturnType<typeof runComparison>>;
      evidence: {OOMKilled: boolean; ExitCode: number;
        Status: string; Running: boolean}}> = [];
    for (const plan of plans) {
      const payload = await runComparison(plan,
        async () => ({status: "succeeded"}), memory);
      payload.results.forEach((row) => {
        row.wallMs = (plan.transformLimit ?? 8) * plan.repeat * 10000;
      });
      rows.push({id: plan.id, imageID: `sha256:${"d".repeat(64)}`,
        verdict: plan.transformLimit === null ? "aborted" : "succeeded",
        payload, evidence: {OOMKilled: false, ExitCode: 0,
          Status: "exited", Running: false}});
    }
    const report = summarizeComparisons(plans, rows);
    assert.equal(report.valid, true);
    assert.equal(report.counts.succeeded, 9);
    assert.equal(report.counts.aborted, 3);
    assert.deepEqual(report.comparisons.map((g) =>
      [g.transformLimit, g.medianMs]),
    [[1, 40000], [2, 80000], [4, 160000], [null, null]]);
    for (const changed of [rows.slice(1), [...rows, rows[0]],
      rows.map((row, index) => index === 0 ?
        {...row, payload: rows[1].payload} : row)]) {
      assert.equal(summarizeComparisons(plans, changed).valid, false);
    }
    assert.equal(summarizeComparisons(makeComparisonPlan(source), rows).valid,
      false);
    assert.equal(summarizeComparisons(plans.slice(1), rows.slice(1)).valid,
      false);
  });
