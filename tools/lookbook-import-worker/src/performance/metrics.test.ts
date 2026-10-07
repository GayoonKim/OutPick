import assert from "node:assert/strict";
import test from "node:test";
import {
  measured, measuredSync, MetricsRecorder, recordBytes, recordJobOutcome,
} from "./metrics.js";
import {withMeasurement} from "./session.js";

const identity = {
  sourceRevision: "a".repeat(40), instanceID: "private-instance",
  mode: "local-assets" as const,
};

function deferred(): {promise: Promise<void>; resolve: () => void} {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}

test("계측 미설정은 원래 Promise와 동기 예외를 그대로 전달한다", async () => {
  const promise = Promise.resolve({ok: true});
  assert.equal(measured("file.upload", () => promise), promise);
  const original = new Error("원본 오류");
  assert.throws(() => measuredSync("image.hash", () => {
    throw original;
  }), (error) => error === original);
  let emitted = false;
  assert.equal(await withMeasurement({
    ...identity, enabled: false, emit: () => {
      emitted = true;
    },
  }, "task", () => promise), await promise);
  assert.equal(emitted, false);
});

test("병렬 요청의 계측을 분리하고 슬롯과 실패 바이트를 집계한다", async () => {
  let now = 0;
  const a = new MetricsRecorder(identity, () => now);
  const b = new MetricsRecorder(identity, () => now);
  const first = deferred();
  const second = deferred();
  const failure = new Error("https://private.example/?token=secret");
  const taskA = a.run(() => Promise.allSettled([
    measured("image.download", async () => {
      recordBytes("image.download", "receivedBytes", 10);
      await first.promise;
    }),
    measured("image.download", async () => {
      recordBytes("image.download", "receivedBytes", 7);
      await second.promise;
      throw failure;
    }),
  ]));
  await b.run(() => measured("image.download", async () => {
    recordBytes("image.download", "receivedBytes", 4);
  }));
  now = 5;
  first.resolve();
  second.resolve();
  await taskA;
  const ra = a.finish("returned");
  const rb = b.finish("returned");
  assert.deepEqual(ra.stages["image.download"], {
    started: 2, succeeded: 1, failed: 1, active: 0, peakActive: 2,
    totalMs: 10, maxMs: 5, receivedBytes: 17,
    submittedBytes: 0, completedBytes: 0,
  });
  assert.equal(rb.stages["image.download"].receivedBytes, 4);
  assert.equal(rb.stages["image.download"].peakActive, 1);
  assert.notEqual(ra.runID, rb.runID);
  assert.equal(ra.complete, true);
  assert.doesNotMatch(JSON.stringify(ra),
    /secret|private-instance|private.example/);
});

test("남아 있는 형제 작업을 완전한 측정으로 보고하지 않는다", async () => {
  const recorder = new MetricsRecorder(identity);
  const barrier = deferred();
  const running = recorder.run(() =>
    measured("file.upload", () => barrier.promise));
  const snapshot = recorder.finish("returned");
  assert.equal(snapshot.complete, false);
  assert.equal(snapshot.stages["file.upload"].active, 1);
  barrier.resolve();
  await running;
  assert.equal(snapshot.stages["file.upload"].active, 1);
});

test("검토 대기와 제품 실패를 Promise 반환 여부와 구분한다", async () => {
  const recorder = new MetricsRecorder(identity);
  await recorder.run(() => measured("job", async () => {
    recordJobOutcome("awaitingReview");
    recordJobOutcome("failed");
    recordJobOutcome("token=secret");
  }));
  const report = recorder.finish("returned");
  assert.deepEqual(report.jobOutcomes,
    {awaitingReview: 1, failed: 1, other: 1});
  assert.equal(report.operationOutcome, "returned");
  assert.doesNotMatch(JSON.stringify(report), /secret/);
});

test("잘못된 바이트 계측은 불완전 판정하고 허위 합계를 만들지 않는다", () => {
  const recorder = new MetricsRecorder(identity);
  recorder.bytes("image.download", "receivedBytes", -1);
  const report = recorder.finish("returned");
  assert.equal(report.complete, false);
  assert.equal(report.stages["image.download"].receivedBytes, 0);
});

test("제품 batch 성능 측정은 민감정보 없이 batchID로 연결한다", () => {
  const recorder = new MetricsRecorder({...identity, batchID: "a".repeat(64)});
  const report = recorder.finish("returned");
  assert.equal(report.batchID, "a".repeat(64));
  assert.doesNotMatch(JSON.stringify(report), /private-instance|token=/);
});

test("요청 계측은 실패 원본을 유지하고 불투명한 실패 결과를 출력한다", async () => {
  const original = new Error("secret URL");
  let report: unknown;
  await assert.rejects(withMeasurement({
    ...identity, enabled: true, emit: (value) => {
      report = value;
    },
  }, "task", async () => {
    throw original;
  }), (error) => error === original);
  assert.ok(report);
  assert.match(JSON.stringify(report), /"operationOutcome":"threw"/);
  assert.doesNotMatch(JSON.stringify(report), /secret URL/);
});

test("계측 출력 실패는 작업 성공이나 원본 실패를 바꾸지 않는다", async () => {
  const options = {
    ...identity, enabled: true, emit: () => {
      throw new Error("sink unavailable");
    },
  };
  assert.equal(await withMeasurement(options, "task", async () => 42), 42);
  const failure = new Error("operation failure");
  await assert.rejects(withMeasurement(options, "task", async () => {
    throw failure;
  }), (error) => error === failure);
});

test("요청 계측은 전달된 제품 batchID만 기록한다", async () => {
  let report: unknown;
  await withMeasurement({...identity, enabled: true, emit: (value) => {
    report = value;
  }}, "task", async () => 42, {batchID: "b".repeat(64)});
  assert.equal((report as {measurement: {batchID: string}}).measurement.batchID,
    "b".repeat(64));
});
