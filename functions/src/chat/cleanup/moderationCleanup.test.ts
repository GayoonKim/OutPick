import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizedClosureRoomName,
  ROOM_TOMBSTONE_TTL_MILLIS,
} from "./moderationCleanup.js";

test("종료 tombstone의 최대 보존 기간은 14일이다", () => {
  assert.equal(ROOM_TOMBSTONE_TTL_MILLIS, 14 * 24 * 60 * 60 * 1000);
});

test("종료 안내에는 유효한 방 이름만 사용한다", () => {
  assert.equal(normalizedClosureRoomName(" QA 채팅방 "), "QA 채팅방");
  assert.equal(normalizedClosureRoomName(" "), null);
  assert.equal(normalizedClosureRoomName("가".repeat(21)), null);
});
