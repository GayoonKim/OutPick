/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  assertReportBurstCapacity,
  nextAcceptedReportAggregate,
  parseSubmitUserReportInput,
  reopenReportState,
  reportMinuteBucket,
  reportPriority,
  reportRateLimitRetryAt,
  reportSubmissionID,
  utf8Snapshot,
} from "./contracts.js";

test("신고 ID는 같은 사건 재전송에 결정적이다", () => {
  const input = {
    reporterModerationPrincipalID: "principal-1",
    targetType: "user" as const,
    targetID: "principal-2",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
  };
  assert.equal(reportSubmissionID(input), reportSubmissionID(input));
  assert.notEqual(
    reportSubmissionID(input),
    reportSubmissionID({...input, clientRequestID: "123e4567-e89b-42d3-a456-426614174001"}),
  );
});

test("terminal review 뒤 새 사건은 open으로 다시 연다", () => {
  assert.deepEqual(reopenReportState({
    exists: true,
    reviewState: "resolved",
    reviewRevision: 2,
    caseVersion: 7,
  }), {
    reviewState: "open",
    reviewRevision: 3,
    caseVersion: 8,
  });
});

test("같은 reporter의 새 사건은 total만 증가시킨다", () => {
  assert.deepEqual(nextAcceptedReportAggregate({
    exists: true,
    reporterExists: true,
    reviewState: "inReview",
    reviewRevision: 0,
    caseVersion: 3,
    uniqueReporterCount: 2,
    totalSubmissionCount: 3,
    reasonCounts: {spam: 1},
    reason: "spam",
  }), {
    reviewState: "inReview",
    reviewRevision: 0,
    caseVersion: 4,
    uniqueReporterCount: 2,
    totalSubmissionCount: 4,
    reasonCounts: {spam: 2},
  });
});

test("1분 10건은 허용하고 다음 고유 사건은 retryAt과 함께 거부한다", () => {
  const now = new Date(119_999);
  assert.doesNotThrow(() => assertReportBurstCapacity(9, now));
  assert.throws(
    () => assertReportBurstCapacity(10, now),
    (error) => error instanceof HttpsError &&
      error.code === "resource-exhausted" &&
      (error.details as {retryAt?: string})?.retryAt ===
        "1970-01-01T00:02:00.000Z",
  );
});

test("긴급 사유와 1분 bucket 경계를 고정한다", () => {
  assert.equal(reportPriority("privacy"), "urgent");
  assert.equal(reportPriority("spam"), "general");
  assert.equal(reportMinuteBucket(new Date(119_999)), 1);
  assert.equal(reportRateLimitRetryAt(new Date(119_999)).getTime(), 120_000);
});

test("snapshot은 Unicode scalar를 깨뜨리지 않고 UTF-8 4000 byte로 제한한다", () => {
  const snapshot = utf8Snapshot("가".repeat(2_000));
  assert(snapshot);
  assert(Buffer.byteLength(snapshot, "utf8") <= 4_000);
  assert.equal(snapshot.includes("�"), false);
});

test("trigger message만 전달한 사용자 신고를 거부한다", () => {
  assert.throws(
    () => parseSubmitUserReportInput({
      targetUID: "user-2",
      reason: "spam",
      triggerMessageID: "message-1",
      clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
    }),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
});
