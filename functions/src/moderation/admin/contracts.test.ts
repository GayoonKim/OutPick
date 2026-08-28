/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  parseIssueMessageEvidenceViewURLInput,
  parseListModerationReportsInput,
  parseMutateAccountModerationInput,
  parseResolveMessageModerationInput,
  requireRecentAdminAuth,
  reviewStateForAction,
} from "./contracts.js";
import {messageQueueQueryContract} from "./service.js";

test("메시지 목록은 명시적인 queue view를 요구한다", () => {
  assert.throws(
    () => parseListModerationReportsInput({targetType: "message"}),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
  assert.equal(parseListModerationReportsInput({
    targetType: "message",
    messageQueueView: "overdueHolding",
  }).messageQueueView, "overdueHolding");
});

test("메시지 관리자 결정은 검토·콘텐츠·계정 조치를 분리해 검증한다", () => {
  const base = {
    incidentID: "incident-1",
    reviewRevision: 0,
    expectedCaseVersion: 2,
    reasonCode: "confirmed-abuse",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
  };
  assert.throws(
    () => parseResolveMessageModerationInput({
      ...base,
      reviewOutcome: "violation",
      contentAction: "keep",
      accountAction: "temporaryRestriction",
    }),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
  const parsed = parseResolveMessageModerationInput({
    ...base,
    reviewOutcome: "violation",
    contentAction: "keep",
    accountAction: "temporaryRestriction",
    restrictedUntil: "2030-01-01T00:00:00.000Z",
    expectedAccountStateVersion: 3,
  });
  assert.equal(parsed.expectedAccountStateVersion, 3);
  assert.equal(parsed.restrictedUntil?.toISOString(), "2030-01-01T00:00:00.000Z");

  assert.throws(
    () => parseResolveMessageModerationInput({
      ...base,
      reviewOutcome: "dismissed",
      contentAction: "delete",
      accountAction: "none",
    }),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
  assert.throws(
    () => parseResolveMessageModerationInput({
      ...base,
      reviewOutcome: "violation",
      contentAction: "keep",
      accountAction: "none",
    }),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
  assert.equal(parseResolveMessageModerationInput({
    ...base,
    reviewOutcome: "violation",
    contentAction: "keep",
    accountAction: "warning",
  }).accountAction, "warning");
  assert.equal(parseResolveMessageModerationInput({
    ...base,
    reviewOutcome: "violation",
    contentAction: "delete",
    accountAction: "none",
  }).contentAction, "delete");
});

test("Evidence URL 입력은 current revision 비교에 필요한 식별자를 모두 요구한다", () => {
  assert.deepEqual(parseIssueMessageEvidenceViewURLInput({
    incidentID: "incident-1",
    reviewRevision: 0,
    evidenceObjectID: "attachment-1",
    objectGeneration: "123",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174001",
  }), {
    incidentID: "incident-1",
    reviewRevision: 0,
    evidenceObjectID: "attachment-1",
    objectGeneration: "123",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174001",
  });
});

test("메시지 관리자 queue 정렬 계약은 view별로 고정된다", () => {
  assert.deepEqual(messageQueueQueryContract("urgent").orders, [
    {field: "slaDueAt", direction: "asc"},
    {field: "lastReportedAt", direction: "desc"},
    {field: "__name__", direction: "asc"},
  ]);
  assert.deepEqual(messageQueueQueryContract("overdueHolding").filters.at(-1),
    ["reviewDueAt", "<=", "serverNow"]);
  assert.deepEqual(messageQueueQueryContract("resolved").orders, [
    {field: "updatedAt", direction: "desc"},
    {field: "__name__", direction: "desc"},
  ]);
});

test("신고 review 상태는 허용된 방향으로만 전이한다", () => {
  assert.equal(reviewStateForAction("open", "startReview"), "inReview");
  assert.equal(reviewStateForAction("inReview", "resolveReview"), "resolved");
  assert.throws(
    () => reviewStateForAction("resolved", "dismissReview"),
    (error) => error instanceof HttpsError && error.code === "failed-precondition",
  );
});

test("고위험 관리자 작업은 5분 이내 인증만 허용한다", () => {
  const now = new Date(1_000_000);
  assert.doesNotThrow(() => requireRecentAdminAuth(800, now));
  assert.throws(
    () => requireRecentAdminAuth(699, now),
    (error) => error instanceof HttpsError && error.code === "unauthenticated",
  );
});

test("일시 제한에는 만료 시각이 필요하다", () => {
  assert.throws(
    () => parseMutateAccountModerationInput({
      targetUID: "user-2",
      action: "temporarilyRestrictAccount",
      reasonCode: "confirmed-abuse",
      expectedStateVersion: 1,
      clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
    }),
    (error) => error instanceof HttpsError && error.code === "invalid-argument",
  );
});
