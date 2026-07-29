import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  canCancelDeletion,
  deletionRequestID,
  parseIntentInput,
  requireRecentAuth,
  retryDelayMillis,
  sha256,
} from "./policy.js";

test("삭제 request ID는 UID와 generation 조합에 대해 결정적이다", () => {
  assert.equal(
    deletionRequestID("uid-a", "generation-a"),
    deletionRequestID("uid-a", "generation-a"),
  );
  assert.notEqual(
    deletionRequestID("uid-a", "generation-a"),
    deletionRequestID("uid-a", "generation-b"),
  );
});

test("nonce hash와 intent 입력을 검증한다", () => {
  assert.equal(sha256("nonce").length, 64);
  assert.deepEqual(parseIntentInput({intentID: "intent", nonce: "nonce"}), {
    intentID: "intent",
    nonce: "nonce",
  });
  assert.throws(() => parseIntentInput({intentID: "a/b", nonce: "nonce"}));
});

test("최근 인증 10분 경계를 검증한다", () => {
  const now = 1_000_000;
  assert.doesNotThrow(() => requireRecentAuth({
    uid: "uid",
    authTimeSeconds: Math.floor(now / 1000) - 600,
    provider: "google.com",
    providerUserID: null,
  }, now));
  assert.throws(
    () => requireRecentAuth({
      uid: "uid",
      authTimeSeconds: Math.floor(now / 1000) - 601,
      provider: "google.com",
      providerUserID: null,
    }, now),
    (error) => error instanceof HttpsError && error.code === "unauthenticated",
  );
});

test("취소는 정확한 만료 시각 직전까지만 가능하다", () => {
  assert.equal(canCancelDeletion(999, 1000), true);
  assert.equal(canCancelDeletion(1000, 1000), false);
  assert.equal(canCancelDeletion(1001, 1000), false);
});

test("재시도 backoff는 5분에서 최대 6시간으로 제한된다", () => {
  assert.equal(retryDelayMillis(1), 5 * 60 * 1000);
  assert.equal(retryDelayMillis(2), 10 * 60 * 1000);
  assert.equal(retryDelayMillis(20), 6 * 60 * 60 * 1000);
});
