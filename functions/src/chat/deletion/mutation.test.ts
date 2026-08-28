import assert from "node:assert/strict";
import test from "node:test";
import {
  cleanupStatusForEvidenceGuard,
  deletionHeadDeliveryJobID,
  messageCleanupJobID,
  messageDeletionDeliveryJobID,
} from "./mutation.js";

test("삭제 cleanup과 delivery ID는 대상과 revision 범위에 대해 결정적이다", () => {
  assert.equal(
    messageCleanupJobID("room", "message"),
    messageCleanupJobID("room", "message"),
  );
  assert.equal(
    messageDeletionDeliveryJobID("room", "message", 42),
    messageDeletionDeliveryJobID("room", "message", 42),
  );
  assert.notEqual(
    messageDeletionDeliveryJobID("room", "message", 42),
    messageDeletionDeliveryJobID("room", "message", 43),
  );
  assert.equal(
    deletionHeadDeliveryJobID("room", 42, 56),
    deletionHeadDeliveryJobID("room", 42, 56),
  );
  assert.notEqual(
    deletionHeadDeliveryJobID("room", 42, 56),
    deletionHeadDeliveryJobID("room", 43, 56),
  );
});

test("report-first media evidence가 끝나기 전에는 공개 cleanup을 대기시킨다", () => {
  assert.equal(cleanupStatusForEvidenceGuard({
    guardWinner: "reportFirst",
    evidenceState: "copyPending",
  }), "awaitingEvidence");
  assert.equal(cleanupStatusForEvidenceGuard({
    guardWinner: "reportFirst",
    evidenceState: "available",
  }), "pending");
  assert.equal(cleanupStatusForEvidenceGuard({
    guardWinner: "reportFirst",
    evidenceState: "failed",
  }), "pending");
  assert.equal(cleanupStatusForEvidenceGuard({
    guardWinner: "deleteFirst",
    evidenceState: "none",
  }), "pending");
});
