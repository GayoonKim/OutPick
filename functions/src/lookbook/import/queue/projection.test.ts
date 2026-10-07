import assert from "node:assert/strict";
import test from "node:test";
import {projectQueueReceipt} from "../../../shared/lookbookQueue/projection.js";
import type {QueueBatch} from "../../../shared/lookbookQueue/model.js";

test(
  "PQ16 batch receipt exposes item execution status and state revision only",
  () => {
    const batch = {
      contractVersion: 1,
      requestID: "123e4567-e89b-42d3-a456-426614174000",
      requestCreatedAt: 1_800_000_000_000,
      requestedBy: "private-user",
      brandID: "brand-1",
      kind: "importSeasons",
      payloadDigest: "private-digest",
      sequence: 1,
      state: "active",
      stateRevision: 8,
      items: [{itemID: "item-1", targetID: "candidate-1", ordinal: 0,
        admissionStatus: "created", processingStatus: "awaitingReview",
        jobID: "job-1", executionID: "execution-1", errorCode: null}],
      preparationAttempts: 1,
      preparationOwner: null,
      dispatchGeneration: 1,
      dispatchState: "delivered",
      createdAt: 1,
      updatedAt: 2,
    } as QueueBatch;

    const receipt = projectQueueReceipt("a".repeat(64), batch);
    assert.equal(receipt.stateRevision, 8);
    assert.equal(receipt.items[0].processingStatus, "awaitingReview");
    assert.equal("requestedBy" in receipt, false);
    assert.equal("payloadDigest" in receipt, false);
  }
);

test("KR01 실행 실패 집계는 접수 실패와 검토 대기를 구분한다", () => {
  const batch = {items: [
    {admissionStatus: "failed", processingStatus: null},
    {admissionStatus: "created", processingStatus: "failed"},
    {admissionStatus: "created", processingStatus: "partialFailed"},
    {admissionStatus: "created", processingStatus: "succeeded"},
    {admissionStatus: "created", processingStatus: "awaitingReview"},
    {admissionStatus: "duplicate", processingStatus: "failed"},
  ]} as QueueBatch;
  const receipt = projectQueueReceipt("batch", batch);
  assert.equal(receipt.failedCount, 1);
  assert.equal(receipt.executionFailedCount, 2);
  assert.equal(receipt.executionSucceededCount, 1);
  assert.equal(receipt.executionReviewCount, 1);
});
