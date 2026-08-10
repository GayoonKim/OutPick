import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizedClosureRoomName,
  shouldCreateClosureNotice,
} from "./moderationCleanup.js";

test("방장 삭제는 방장을 제외한 참여자에게만 안내한다", () => {
  assert.equal(
    shouldCreateClosureNotice("owner", "owner", "closedByOwner"), false);
  assert.equal(
    shouldCreateClosureNotice("member", "owner", "closedByOwner"), true);
});

test("관리자 종료는 방장을 포함한 모든 참여자에게 안내한다", () => {
  assert.equal(
    shouldCreateClosureNotice("owner", "owner", "closedByModeration"), true);
  assert.equal(
    shouldCreateClosureNotice("member", "owner", "closedByModeration"), true);
});

test("종료 안내에는 유효한 방 이름만 사용한다", () => {
  assert.equal(normalizedClosureRoomName(" QA 채팅방 "), "QA 채팅방");
  assert.equal(normalizedClosureRoomName(" "), null);
  assert.equal(normalizedClosureRoomName("가".repeat(21)), null);
});
