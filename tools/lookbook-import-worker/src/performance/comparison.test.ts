import assert from "node:assert/strict";
import test from "node:test";
import {ARMS, comparisonInputs, comparisonPolicy, makeComparisonPlan,
  runComparison, validateComparisonPlan} from "./comparison.js";
import {BufferInventory} from "./buffer-inventory.js";

const source = {sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  inputDigest: "c".repeat(64)};
const memory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};

test("54회 계획은 모든 구조 부하 반복을 포함하고 승인한 정책과 묶인다", () => {
  const plans = makeComparisonPlan(source);
  assert.equal(plans.length, 54);
  assert.equal(new Set(plans.map((row) => row.id)).size, 54);
  for (const arm of ARMS) {
    assert.equal(plans.filter((row) => row.arm === arm).length, 9);
    const policy = comparisonPolicy(arm);
    assert.equal(policy.reuse, "off");
    assert.equal(policy.seasons.order,
      ["D", "E"].includes(arm) ? "serial-per-brand" : "parallel");
    if (arm === "A") assert.equal(policy.pipeline, null);
    if (["B", "D"].includes(arm)) {
      assert.deepEqual(policy.pipeline?.assets,
        {kind: "batch", size: 8, concurrency: null});
    }
    if (["C", "E"].includes(arm)) {
      assert.deepEqual(policy.pipeline?.limits,
        {download: 4, transform: 2, upload: 4, paths: null});
    }
    if (arm === "F") {
      assert.equal(policy.seasons.concurrency, null);
      assert.ok(policy.pipeline);
      assert.ok(Object.values(policy.pipeline.limits)
        .every((x) => x === null));
    }
  }
  plans.forEach(validateComparisonPlan);
  assert.throws(() => validateComparisonPlan({...plans[0], arm: "F"}));
  assert.throws(() => makeComparisonPlan({...source, inputDigest: "invalid"}));
  assert.deepEqual(comparisonInputs("synthetic-three").map((x) => x.brandID),
    ["synthetic-2026", "synthetic-2026", "synthetic-2025", "synthetic-2025",
      "synthetic-2024", "synthetic-2024"]);
});

test("비교 실행은 추출 검토와 승인 후 저장을 분리하고 두 구간을 검증한다",
  async () => {
    for (const arm of ARMS) {
      const plan = makeComparisonPlan(source).find((p) => p.arm === arm &&
        p.load === "single" && p.repeat === 1);
      assert.ok(plan);
      const phases: string[] = [];
      const result = await runComparison(plan, async (phase, _season, ctx) => {
        assert.equal(ctx.pipeline === undefined, arm === "A");
        phases.push(phase);
        return {status: phase === "local-extraction" ?
          "needs-review" : "succeeded"};
      }, memory);
      assert.deepEqual(phases, ["local-extraction", "local-assets"]);
      assert.equal(result.validation.valid, true);
      assert.equal(result.validation.eligibleIDs.length, 2);
    }
  });

test("비교 실행의 실패와 환경 미준비는 누락 구간까지 결과에 남는다",
  async () => {
    const plan = makeComparisonPlan(source)[0];
    const failed = await runComparison(plan, async () => ({status: "failed"}),
      memory);
    assert.deepEqual(failed.results.map((x) => x.outcome),
      ["failed", "aborted"]);
    assert.equal(failed.validation.valid, true);
    assert.equal(failed.validation.eligibleIDs.length, 0);
    const unavailable = await runComparison(plan, async () =>
      assert.fail("실행 불가"), {maxSampleGapMs: 500,
      readMemory: async () => null});
    assert.ok(unavailable.results.every((x) => x.outcome === "unavailable"));
    assert.equal(unavailable.validation.valid, true);
  });

test("비교 관측 외부의 독립 보유량은 실험 결과에 섞이지 않는다", async () => {
  const unrelated = new BufferInventory();
  await unrelated.run(async () => {
    const release = unrelated.retain("source", Buffer.alloc(10));
    const result = await runComparison(makeComparisonPlan(source)[0],
      async () => ({status: "succeeded"}), memory);
    assert.equal(result.validation.eligibleIDs.length, 2);
    assert.equal(unrelated.snapshot().currentBytes, 10);
    release();
  });
});

test("계측 off는 같은 실행에서 별도 설정 식별자와 빈 보고서를 기록한다",
  async () => {
    const plan = makeComparisonPlan(source)[0];
    const events: string[] = [];
    const execute: Parameters<typeof runComparison>[1] = async (phase) => {
      events.push(phase);
      return {status: "succeeded"};
    };
    const on = await runComparison(plan, execute, memory);
    const off = await runComparison(plan, execute, memory, false);
    assert.deepEqual(events.slice(0, 2), events.slice(2));
    assert.equal(off.measurementEnabled, false);
    assert.equal(off.validation.eligibleIDs.length, 2);
    assert.ok(off.results.every((row) => row.reports.length === 0));
    assert.notEqual(on.results[0].settingsDigest,
      off.results[0].settingsDigest);
  });
