import assert from "node:assert/strict";
import test from "node:test";
import {
  effectiveModerationStatus,
  rejectMissingCapability
} from "../../src/moderation/capabilities.js";

test("만료된 제한은 socket 요청 시각에 active로 판정한다", () => {
  const status = effectiveModerationStatus({
    moderationStatus: "restricted",
    restrictedUntil: { toMillis: () => 1_000 }
  }, 2_000);
  assert.equal(status, "active");
});

test("restricted socket은 메시지 생성 capability를 거부한다", () => {
  let ack;
  const rejected = rejectMissingCapability({
    allowedCapabilities: ["readAppContent", "report"]
  }, "createUGC", (value) => { ack = value; });
  assert.equal(rejected, true);
  assert.equal(ack.error, "moderation_capability_denied");
});
