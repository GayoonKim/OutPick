/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  parseMutateAccountModerationInput,
  requireRecentAdminAuth,
  reviewStateForAction,
} from "./contracts.js";

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
