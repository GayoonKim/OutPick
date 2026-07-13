/* eslint-disable require-jsdoc, max-len, brace-style, block-spacing */
import assert from "node:assert/strict";
import test from "node:test";
import {
  cleanupExpiredMediaUploads,
  didRoomTransitionToClosed,
  type ChatMediaCleanupDependencies,
  type ExpiredMediaUpload,
} from "./cleanupService.js";

function upload(overrides: Partial<ExpiredMediaUpload> = {}): ExpiredMediaUpload {
  return {
    roomID: "room-1",
    messageID: "message-1",
    storagePrefix: "rooms/room-1/messages/message-1",
    ...overrides,
  };
}

function dependencies(events: string[]): ChatMediaCleanupDependencies {
  return {
    messageExists: async () => false,
    deleteReservation: async () => { events.push("reservation"); },
    markCleanupFailed: async (_upload, reason) => { events.push(`failed:${reason}`); },
    deleteStoragePrefix: async () => { events.push("storage"); },
    logDeleted: () => { events.push("logged"); },
    logFailure: () => { events.push("error-logged"); },
  };
}

test("room close는 false에서 true로 바뀐 경우만 인정한다", () => {
  assert.equal(didRoomTransitionToClosed({isClosed: false}, {isClosed: true}), true);
  assert.equal(didRoomTransitionToClosed({isClosed: true}, {isClosed: true}), false);
  assert.equal(didRoomTransitionToClosed({isClosed: false}, {isClosed: false}), false);
  assert.equal(didRoomTransitionToClosed(undefined, {isClosed: true}), false);
});

test("메시지가 없으면 Storage prefix 후 예약 문서를 삭제한다", async () => {
  const events: string[] = [];
  await cleanupExpiredMediaUploads([upload()], dependencies(events));
  assert.deepEqual(events, ["storage", "reservation", "logged"]);
});

test("메시지가 존재하면 Storage를 유지하고 예약만 삭제한다", async () => {
  const events: string[] = [];
  const deps = dependencies(events);
  deps.messageExists = async () => true;
  await cleanupExpiredMediaUploads([upload()], deps);
  assert.deepEqual(events, ["reservation"]);
});

test("잘못된 예약과 prefix는 실패 상태로 기록한다", async () => {
  const events: string[] = [];
  await cleanupExpiredMediaUploads([
    upload({roomID: null}),
    upload({storagePrefix: "other/path"}),
  ], dependencies(events));
  assert.deepEqual(events, [
    "failed:invalid_reservation",
    "failed:storage_prefix_mismatch",
  ]);
});

test("Storage 삭제 실패를 기록하고 다음 예약을 계속 처리한다", async () => {
  const events: string[] = [];
  const deps = dependencies(events);
  let attempt = 0;
  deps.deleteStoragePrefix = async () => {
    attempt += 1;
    if (attempt === 1) throw new Error("storage unavailable");
    events.push("storage");
  };
  await cleanupExpiredMediaUploads([
    upload(),
    upload({messageID: "message-2", storagePrefix: "rooms/room-1/messages/message-2"}),
  ], deps);
  assert.deepEqual(events, [
    "error-logged",
    "failed:storage unavailable",
    "storage",
    "reservation",
    "logged",
  ]);
});
