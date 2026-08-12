import assert from "node:assert/strict";
import test from "node:test";

import { createRoomBanWatcher } from "../../src/rooms/roomBanWatcher.js";

test("활성 방 밴은 같은 principal socket만 알리고 즉시 방에서 제거한다", () => {
  let onSnapshot;
  const db = {
    collectionGroup(name) {
      assert.equal(name, "bans");
      return {
        onSnapshot(success) {
          onSnapshot = success;
          return () => {};
        }
      };
    }
  };
  const emitted = [];
  const leaves = [];
  const target = {
    username: "Target",
    moderationPrincipalID: "principal-target",
    emit: (event, payload) => emitted.push({ event, payload }),
    leave: (roomID) => leaves.push(roomID)
  };
  const other = {
    username: "Other",
    moderationPrincipalID: "principal-other",
    emit() { throw new Error("다른 principal에는 emit하면 안 됩니다."); },
    leave() { throw new Error("다른 principal은 leave하면 안 됩니다."); }
  };
  const roomEmits = [];
  const io = {
    to: (roomID) => ({
      emit: (event, payload) => roomEmits.push({ roomID, event, payload })
    }),
    sockets: {
      adapter: { rooms: new Map([["room-1", new Set(["target", "other"]) ]]) },
      sockets: new Map([["target", target], ["other", other]])
    }
  };
  const rooms = { "room-1": ["Target", "Other"] };
  createRoomBanWatcher({ db, io, rooms }).start();
  const change = {
    type: "added",
    doc: {
      id: "principal-target",
      ref: { parent: { parent: { id: "room-1" } } },
      data: () => ({ isActive: true, stateVersion: 3 })
    }
  };

  onSnapshot({ docChanges: () => [change] });
  onSnapshot({ docChanges: () => [{ ...change, type: "modified" }] });

  assert.deepEqual(emitted, [{
    event: "room:membership-removed",
    payload: { roomID: "room-1", reason: "room_banned", stateVersion: 3 }
  }]);
  assert.deepEqual(leaves, ["room-1"]);
  assert.deepEqual(rooms["room-1"], ["Other"]);
  assert.equal(roomEmits.at(-1).event, "user list");
});

test("비활성 밴과 removed change는 socket 상태를 변경하지 않는다", () => {
  let onSnapshot;
  const db = { collectionGroup: () => ({ onSnapshot: (success) => { onSnapshot = success; } }) };
  let changed = false;
  const io = {
    to: () => ({ emit: () => { changed = true; } }),
    sockets: {
      adapter: { rooms: new Map([["room-1", new Set(["socket-1"]) ]]) },
      sockets: new Map([["socket-1", {
        moderationPrincipalID: "principal-target",
        emit: () => { changed = true; },
        leave: () => { changed = true; }
      }]])
    }
  };
  createRoomBanWatcher({ db, io, rooms: {} }).start();
  const document = {
    id: "principal-target",
    ref: { parent: { parent: { id: "room-1" } } },
    data: () => ({ isActive: false, stateVersion: 4 })
  };
  onSnapshot({ docChanges: () => [
    { type: "modified", doc: document },
    { type: "removed", doc: { ...document, data: () => ({ isActive: true }) } }
  ] });
  assert.equal(changed, false);
});
