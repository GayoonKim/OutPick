import assert from "node:assert/strict";
import test from "node:test";
import {
  isQueueExecutionTerminal, parseBatchDelivery, progressFingerprint,
} from "./coordinator.js";

test("PQ03 묶음 전달은 고정된 식별자 세대 계약만 허용한다", () => {
  const input = {batchID: "a".repeat(64),
    dispatchGeneration: 0, queueContractVersion: 1};
  assert.deepEqual(parseBatchDelivery(input), input);
  for (const patch of [{batchID: "../other"}, {batchID: `${"a".repeat(64)}\n`},
    {dispatchGeneration: -1}, {dispatchGeneration: 0.5},
    {queueContractVersion: 5},
    {owner: "client-owner"}]) {
    assert.throws(() => parseBatchDelivery({...input, ...patch}),
      /INVALID_QUEUE_CONTRACT/);
  }
});

test("PQ07 영속 진행 fingerprint는 키 순서에 독립적이고 실제 변경을 구분한다", () => {
  assert.equal(progressFingerprint({b: "done", a: "parsed"}),
    progressFingerprint({a: "parsed", b: "done"}));
  assert.notEqual(progressFingerprint({a: "parsed"}),
    progressFingerprint({a: "stored"}));
  assert.throws(() => progressFingerprint({a: ""}), /INVALID_QUEUE_PROGRESS/);
});

test("PQ03 교정 필요 결과도 현재 실행의 종료 상태로 인정한다", () => {
  assert.equal(isQueueExecutionTerminal("correctionRequired"), true);
  assert.equal(isQueueExecutionTerminal("awaitingReview"), true);
  assert.equal(isQueueExecutionTerminal("recoveryRequired"), false);
  assert.equal(isQueueExecutionTerminal("active"), false);
});
