/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {
  moderationAliasID,
  providerIdentityFromUserRecord,
  resolveProviderIdentity,
} from "./identity.js";

test("alias ID는 provider subject 원문을 노출하지 않고 결정적으로 생성한다", () => {
  const identity = {provider: "apple" as const, subject: "private-subject"};
  const first = moderationAliasID(identity, "test-secret");
  const second = moderationAliasID(identity, "test-secret");
  assert.equal(first, second);
  assert.match(first, /^v1_[A-Za-z0-9_-]{43}$/);
  assert.equal(first.includes(identity.subject), false);
});

test("Kakao의 서버 검증 custom claim에서 stable subject를 읽는다", async () => {
  const result = await resolveProviderIdentity({
    uid: "firebase-uid",
    token: {provider: "kakao", providerUserID: "12345"},
  });
  assert.deepEqual(result, {
    uid: "firebase-uid",
    identity: {provider: "kakao", subject: "12345"},
  });
});

test("Google Firebase identities에서 stable subject를 읽는다", async () => {
  const result = await resolveProviderIdentity({
    uid: "firebase-uid",
    token: {
      firebase: {
        sign_in_provider: "google.com",
        identities: {"google.com": ["google-subject"]},
      },
    },
  });
  assert.equal(result.identity.provider, "google");
  assert.equal(result.identity.subject, "google-subject");
});

test("backfill은 Google·Apple providerData와 Kakao custom claim을 분류한다", () => {
  assert.deepEqual(providerIdentityFromUserRecord({
    uid: "google-uid",
    providerData: [{providerId: "google.com", uid: "google-subject"}],
  }), {provider: "google", subject: "google-subject"});
  assert.deepEqual(providerIdentityFromUserRecord({
    uid: "apple-uid",
    providerData: [{providerId: "apple.com", uid: "apple-subject"}],
  }), {provider: "apple", subject: "apple-subject"});
  assert.deepEqual(providerIdentityFromUserRecord({
    uid: "kakao-uid",
    customClaims: {provider: "kakao", providerUserID: "12345"},
    providerData: [],
  }), {provider: "kakao", subject: "12345"});
});

test("backfill은 지원 identity 누락과 다중 provider 연결을 불명확하게 분류한다", () => {
  assert.equal(providerIdentityFromUserRecord({
    uid: "password-uid",
    providerData: [{providerId: "password", uid: "email@example.com"}],
  }), null);
  assert.equal(providerIdentityFromUserRecord({
    uid: "linked-uid",
    providerData: [
      {providerId: "google.com", uid: "google-subject"},
      {providerId: "apple.com", uid: "apple-subject"},
    ],
  }), null);
});
