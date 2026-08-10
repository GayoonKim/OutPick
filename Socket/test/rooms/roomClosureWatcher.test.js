import assert from "node:assert/strict";
import test from "node:test";

import { createRoomClosureWatcher } from "../../src/rooms/roomClosureWatcher.js";

test("room cleanup job listener는 폐쇄 이벤트를 한 번 emit하고 socket을 방에서 제거한다", () => {
  let onSnapshot;
  const db = {
    collection: (name) => {
      assert.equal(name, "moderationRoomCleanupJobs");
      return {
        onSnapshot: (success) => {
          onSnapshot = success;
          return () => {};
        }
      };
    }
  };
  const emitted = [];
  const leaves = [];
  const io = {
    to: (roomID) => ({
      emit: (event, payload) => emitted.push({ roomID, event, payload })
    }),
    sockets: {
      adapter: { rooms: new Map([["room-1", new Set(["socket-1"]) ]]) },
      sockets: new Map([["socket-1", { leave: (roomID) => leaves.push(roomID) }]])
    }
  };
  const rooms = { "room-1": { roomName: "닫힐 방" } };
  createRoomClosureWatcher({ db, io, rooms }).start();
  const change = {
    type: "added",
    doc: {
      id: "room-1",
      data: () => ({
        roomID: "room-1",
        closureType: "closedByModeration",
        closureNoticeCode: "communityGuidelineViolation",
        lifecycleVersion: 2,
        status: "pending"
      })
    }
  };

  onSnapshot({ docChanges: () => [change] });
  onSnapshot({ docChanges: () => [{ ...change, type: "modified" }] });

  assert.equal(emitted.length, 1);
  assert.deepEqual(emitted[0], {
    roomID: "room-1",
    event: "room:closed",
    payload: {
      roomID: "room-1",
      closureType: "closedByModeration",
      closureNoticeCode: "communityGuidelineViolation",
      lifecycleVersion: 2
    }
  });
  assert.deepEqual(leaves, ["room-1"]);
  assert.equal(rooms["room-1"], undefined);
});

test("완료 job도 폐쇄 이벤트로 처리하고 잘못된 job만 무시한다", () => {
  let onSnapshot;
  const db = {
    collection: () => ({
      onSnapshot: (success) => {
        onSnapshot = success;
        return () => {};
      }
    })
  };
  let emitCount = 0;
  const io = {
    to: () => ({ emit: () => { emitCount += 1; } }),
    sockets: { adapter: { rooms: new Map() }, sockets: new Map() }
  };
  createRoomClosureWatcher({ db, io, rooms: {} }).start();

  onSnapshot({
    docChanges: () => [
      { type: "added", doc: { id: "done", data: () => ({
        status: "completed",
        closureType: "closedByOwner",
        lifecycleVersion: 2
      }) } },
      { type: "added", doc: { id: "bad/type", data: () => ({
        status: "pending", closureType: "closedByOwner"
      }) } },
      { type: "removed", doc: { id: "room", data: () => ({
        status: "pending", closureType: "closedByOwner"
      }) } }
    ]
  });

  assert.equal(emitCount, 1);
});
