import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {deletionAuthContext} from "./functions.js";

test("Firebase와 Kakao token claim을 삭제 auth context로 변환한다", () => {
  assert.deepEqual(deletionAuthContext({
    uid: "google-user",
    token: {
      auth_time: 100,
      firebase: {sign_in_provider: "google.com"},
    },
  }), {
    uid: "google-user",
    authTimeSeconds: 100,
    provider: "google.com",
    providerUserID: null,
  });
  assert.deepEqual(deletionAuthContext({
    uid: "kakao:1234",
    token: {
      auth_time: 200,
      provider: "kakao",
      providerUserID: "1234",
    },
  }), {
    uid: "kakao:1234",
    authTimeSeconds: 200,
    provider: "kakao",
    providerUserID: "1234",
  });
});

test("삭제 auth context는 미인증 요청을 거부한다", () => {
  assert.throws(
    () => deletionAuthContext(undefined),
    (error) => error instanceof HttpsError && error.code === "unauthenticated",
  );
});
