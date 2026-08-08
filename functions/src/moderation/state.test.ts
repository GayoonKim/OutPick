/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {allowedCapabilities, effectiveModerationState} from "./state.js";

test("만료된 restricted 상태는 요청 시각에 active로 판정한다", () => {
  const state = effectiveModerationState({
    moderationStatus: "restricted",
    restrictedUntil: Timestamp.fromMillis(1_000),
    stateVersion: 3,
  }, new Date(2_000));
  assert.equal(state.moderationStatus, "active");
  assert.equal(state.restrictedUntil, null);
});

test("restricted capability는 읽기·신고·차단·본인 삭제만 허용한다", () => {
  const capabilities = allowedCapabilities("restricted");
  assert.equal(capabilities.includes("readAppContent"), true);
  assert.equal(capabilities.includes("report"), true);
  assert.equal(capabilities.includes("deleteOwnUGC"), true);
  assert.equal(capabilities.includes("createUGC"), false);
  assert.equal(capabilities.includes("joinRoom"), false);
});
