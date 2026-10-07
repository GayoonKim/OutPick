import assert from "node:assert/strict";
import test from "node:test";
import {MetricsRecorder} from "./metrics.js";
import {median, validateResultSet, type PlannedRun} from "./result.js";

const plan: PlannedRun = {
  id: "on-1", sourceRevision: "a".repeat(40),
  sourceDigest: "b".repeat(64), inputDigest: "c".repeat(64),
  settingsDigest: "d".repeat(64), mode: "local-assets", measurementCount: 1,
};
function result() {
  let now = 0;
  const recorder = new MetricsRecorder(
    {...plan, instanceID: "test"}, () => now);
  const end = recorder.begin("image.transform");
  now = 10;
  end(true);
  return {
    id: plan.id, sourceDigest: plan.sourceDigest, inputDigest: plan.inputDigest,
    settingsDigest: plan.settingsDigest, outcome: "succeeded", reason: null,
    correct: true, wallMs: 11,
    reports: [{measurement: recorder.finish("returned"), resources: {
      samples: 2, samplingErrors: 0, missedTicks: 0,
      missingContainerSamples: 2, maxSampleGapMs: 10,
      containerMemoryAvailable: false,
      cpuUserMicros: 100, cpuSystemMicros: 10, maxRSSBytes: 1000,
      maxHeapUsedBytes: 100, maxExternalBytes: 100, maxArrayBufferBytes: 100,
      maxSharpQueue: 0, maxSharpProcess: 1, sharpConcurrency: 1,
      eventLoopMaxMs: 0, eventLoopMeanMs: null,
      sampleIntervalMs: 100, maxContainerRatio: null,
    }}],
  };
}

test("실험 결과는 계획한 입력 설정 소스의 일치를 요구한다", () => {
  assert.equal(validateResultSet([plan], [result()]).valid, true);
  for (const key of ["sourceDigest", "inputDigest", "settingsDigest"]) {
    assert.equal(validateResultSet([plan], [{
      ...result(), [key]: "e".repeat(64),
    }]).valid, false, key);
  }
  const row = result();
  row.reports[0].measurement.inputDigest = null;
  assert.equal(validateResultSet([plan], [row]).valid, false);
});

test("실험 회차 누락 중복 추가와 빈 계획은 비교를 차단한다", () => {
  for (const rows of [[], [result(), result()], [{...result(), id: "extra"}]]) {
    const verdict = validateResultSet([plan], rows);
    assert.equal(verdict.valid, false);
    assert.deepEqual(verdict.eligibleIDs, []);
  }
  assert.equal(validateResultSet([], []).valid, false);
  assert.equal(validateResultSet([plan, plan], [result()]).valid, false);
});

test("실패 중단 환경 미준비는 원래 분모와 결과에 남긴다", () => {
  const outcomes = ["failed", "aborted", "unavailable"];
  const plans = outcomes.map((id) => ({...plan, id}));
  const rows = outcomes.map((outcome) => ({
    ...result(), id: outcome, outcome, correct: null,
    reason: "environment", wallMs: null, reports: [],
  }));
  const verdict = validateResultSet(plans, rows);
  assert.equal(verdict.valid, true);
  assert.equal(verdict.planned, 3);
  assert.equal(verdict.recorded, 3);
  assert.deepEqual(verdict.counts,
    {succeeded: 0, failed: 1, aborted: 1, unavailable: 1});
  assert.deepEqual(verdict.eligibleIDs, []);
});

test("불완전 계측 거짓 정상 종료와 잘못된 수치는 성공 표본이 아니다", () => {
  const incomplete = result();
  incomplete.reports[0].measurement.complete = false;
  const active = result();
  active.reports[0].measurement.stages["image.transform"].active = 1;
  const invalidBytes = result();
  invalidBytes.reports[0].measurement.stages["image.hash"].receivedBytes = NaN;
  const backwards = result();
  backwards.reports[0].measurement.durationMs = 12;
  const resourceError = result();
  resourceError.reports[0].resources.samplingErrors = 1;
  for (const row of [incomplete, active, invalidBytes, backwards, resourceError,
    {...result(), correct: false}, {...result(), wallMs: null},
    {...result(), reports: []}, {...result(), outcome: "unknown"}, null]) {
    assert.equal(validateResultSet([plan], [row]).valid, false);
  }
});

test("다른 회차에 같은 계측 레코드를 재사용하면 거절한다", () => {
  const row = result();
  const verdict = validateResultSet([plan, {...plan, id: "on-2"}], [
    row, {...row, id: "on-2"},
  ]);
  assert.equal(verdict.valid, false);
  assert.deepEqual(verdict.eligibleIDs, []);
});

test("계측 off의 명시적 계획만 계측 레코드 없이 비교할 수 있다", () => {
  const row = {...result(), reports: []};
  assert.equal(validateResultSet([plan], [row]).valid, false);
  assert.equal(validateResultSet([{...plan, measurementCount: 0}], [row])
    .valid, true);
});

test("중앙값은 홀수 짝수와 잘못된 표본을 구분한다", () => {
  const input = [100, 1, 2];
  assert.equal(median(input), 2);
  assert.deepEqual(input, [100, 1, 2]);
  assert.equal(median([1, 9, 2, 4]), 3);
  for (const values of [[], [NaN], [Infinity], [-1]]) {
    assert.throws(() => median(values));
  }
});
