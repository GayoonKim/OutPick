import assert from "node:assert/strict";
import test from "node:test";
import {makeComparisonPlan} from "./comparison.js";
import {assessOverhead, overheadCases, runOverhead} from "./overhead.js";

const plan = makeComparisonPlan({sourceRevision: "a".repeat(40),
  sourceDigest: "b".repeat(64), inputDigest: "c".repeat(64)})[0];
const memory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};
const successful = () => runOverhead(plan,
  async () => ({status: "succeeded"}), memory);

test("오버헤드는 준비 두 번을 제외한 교차 다섯 쌍만 비교한다", async () => {
  const payload = await successful();
  assert.deepEqual(overheadCases().map((x) => x.enabled),
    [false, true, false, true, true, false, false, true,
      true, false, false, true]);
  for (const entry of payload.cases) {
    assert.ok(entry.result);
    for (const row of entry.result.results) {
      row.wallMs = entry.warmup ? 999999 : entry.enabled ? 200000 : 100000;
    }
  }
  const result = assessOverhead(plan, payload);
  assert.equal(result.valid, true);
  assert.equal(result.comparison?.pairs.length, 5);
  assert.equal(result.comparison?.offMedianMs, 200000);
  assert.equal(result.comparison?.changePercent, 100);
});

test("오버헤드는 누락 중복 계측 재사용과 환경 오류를 거절한다", async () => {
  const payload = await successful();
  assert.equal(assessOverhead(plan, payload).valid, true);
  const missing = structuredClone(payload);
  missing.cases.pop();
  assert.equal(assessOverhead(plan, missing).valid, false);
  const duplicate = structuredClone(payload);
  duplicate.cases[3] = duplicate.cases[1];
  assert.equal(assessOverhead(plan, duplicate).valid, false);
  const reused = structuredClone(payload);
  reused.cases[3].result = reused.cases[1].result;
  assert.equal(assessOverhead(plan, reused).valid, false);
  const invalid = structuredClone(payload);
  assert.ok(invalid.cases[0].result);
  invalid.cases[0].result.memory.limitBytes = 1;
  assert.equal(assessOverhead(plan, invalid).valid, false);
});

test("오버헤드 준비 실패는 후속 작업을 막고 미실행 회차도 기록한다",
  async () => {
    let calls = 0;
    const journal: string[] = [];
    const payload = await runOverhead(plan, async () => {
      calls++;
      return {status: "failed"};
    }, memory, async (entry) => {
      journal.push(entry.id);
    });
    assert.equal(calls, 1);
    assert.equal(journal.length, 12);
    assert.equal(payload.cases.filter((x) => x.result === null).length, 11);
    assert.equal(assessOverhead(plan, payload).valid, false);
  });
