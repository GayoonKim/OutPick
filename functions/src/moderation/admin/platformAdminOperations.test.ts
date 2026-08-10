import assert from "node:assert/strict";
import test from "node:test";
import {
  assertPlatformAdminOperationGate,
  platformAdminProvider,
} from "./platformAdminOperations.js";

test("Auth 사용자를 민감정보 출력 없이 provider로 분류한다", () => {
  assert.equal(platformAdminProvider("google-uid", ["google.com"]), "google");
  assert.equal(platformAdminProvider("kakao:123", []), "kakao");
  assert.equal(platformAdminProvider("ambiguous", []), null);
  assert.equal(platformAdminProvider("kakao:123", ["google.com"]), null);
});

test("Production grant는 exact confirmation과 예상 건수를 요구한다", () => {
  const base = {
    projectID: "outpick-664ae",
    operation: "grant" as const,
    apply: true,
    confirmation: "GRANT_SINGLE_PLATFORM_ADMIN_TO_OUTPICK_664AE",
    expectedAuthCount: 2,
    actualAuthCount: 2,
    expectedProviderCount: 1,
    actualProviderCount: 1,
  };
  assert.doesNotThrow(() => assertPlatformAdminOperationGate(base));
  assert.throws(() => assertPlatformAdminOperationGate({
    ...base,
    confirmation: "wrong",
  }));
  assert.throws(() => assertPlatformAdminOperationGate({
    ...base,
    actualAuthCount: 3,
  }));
});

test("audit apply와 다중 provider target을 거부한다", () => {
  assert.throws(() => assertPlatformAdminOperationGate({
    projectID: "outpick-test",
    operation: "audit",
    apply: true,
    confirmation: null,
    expectedAuthCount: null,
    actualAuthCount: 2,
    expectedProviderCount: null,
    actualProviderCount: 0,
  }));
  assert.throws(() => assertPlatformAdminOperationGate({
    projectID: "outpick-test",
    operation: "grant",
    apply: true,
    confirmation: null,
    expectedAuthCount: null,
    actualAuthCount: 2,
    expectedProviderCount: null,
    actualProviderCount: 2,
  }));
});
