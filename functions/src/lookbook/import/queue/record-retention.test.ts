import assert from "node:assert/strict";
import test from "node:test";
import {QUEUE_POLICY} from "./contracts.js";
import {decideBatchRetention} from "./record-retention.js";

const releasedAt = 1_000;
const success = {batchState: "released", releasedAt,
  receiptExpiresAt: releasedAt + QUEUE_POLICY.receiptRetentionMs,
  linkedStates: [{status: "succeeded", priorFailure: false}],
  admissionFailure: false};

test("PQ12 성공 상세는 24시간 이후 정리하고 최소 영수증은 30일 유지한다", () => {
  assert.equal(decideBatchRetention({...success,
    now: releasedAt + QUEUE_POLICY.successDetailRetentionMs - 1}), "notDue");
  assert.equal(decideBatchRetention({...success,
    now: releasedAt + QUEUE_POLICY.successDetailRetentionMs}), "pruneDetails");
  assert.equal(decideBatchRetention({...success, detailsPruned: true,
    now: releasedAt + QUEUE_POLICY.receiptRetentionMs - 1}), "notDue");
  assert.equal(decideBatchRetention({...success, detailsPruned: true,
    now: releasedAt + QUEUE_POLICY.receiptRetentionMs}), "deleteReceipt");
});

test("PQ12 실패 이력은 30일 상세를 보존하고 검토·미종료 실행은 보호한다", () => {
  const failed = {...success,
    linkedStates: [{status: "succeeded", priorFailure: true}]};
  assert.equal(decideBatchRetention({...failed,
    now: releasedAt + QUEUE_POLICY.resolvedFailureRetentionMs - 1}),
  "deferFailure");
  assert.equal(decideBatchRetention({...failed,
    now: releasedAt + QUEUE_POLICY.resolvedFailureRetentionMs}),
  "pruneDetails");
  assert.equal(decideBatchRetention({...success,
    linkedStates: [{status: "awaitingReview", priorFailure: false}],
    now: releasedAt + QUEUE_POLICY.receiptRetentionMs}), "protect");
  assert.equal(decideBatchRetention({...success,
    linkedStates: [{status: "active", priorFailure: false}],
    now: releasedAt + QUEUE_POLICY.receiptRetentionMs}), "protect");
});
