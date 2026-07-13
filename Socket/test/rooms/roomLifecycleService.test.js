import assert from "node:assert/strict";
import test from "node:test";

import { createRoomLifecycleService } from "../../src/rooms/roomLifecycleService.js";

function makeDB({ exists, creatorUID }) {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({
          exists,
          data: () => ({ creatorUID })
        })
      })
    })
  };
}

test("room lifecycle service는 owner close와 participant leave를 구분한다", async () => {
  const closeCalls = [];
  const ownerService = createRoomLifecycleService({
    db: makeDB({ exists: true, creatorUID: "owner" }),
    closeRoomImmediately: async (value) => { closeCalls.push(value); return { ok: true }; },
    leaveRoomMembership: async () => ({ ok: true })
  });
  assert.deepEqual(
    await ownerService.leaveOrClose({ roomID: "room", userUID: "owner" }),
    { ok: true, mode: "closed" }
  );
  assert.deepEqual(closeCalls, [{ roomID: "room", closedByUID: "owner" }]);

  const leaveCalls = [];
  const participantService = createRoomLifecycleService({
    db: makeDB({ exists: true, creatorUID: "owner" }),
    closeRoomImmediately: async () => ({ ok: true }),
    leaveRoomMembership: async (value) => { leaveCalls.push(value); return { ok: true }; }
  });
  assert.deepEqual(
    await participantService.leaveOrClose({ roomID: "room", userUID: "member" }),
    { ok: true, mode: "left" }
  );
  assert.deepEqual(leaveCalls, [{ roomID: "room", userUID: "member" }]);
});

test("이미 삭제된 room을 별도 socket side effect 없는 closed 결과로 표시한다", async () => {
  const service = createRoomLifecycleService({
    db: makeDB({ exists: false }),
    closeRoomImmediately: async () => ({ ok: true }),
    leaveRoomMembership: async () => ({ ok: true })
  });

  assert.deepEqual(
    await service.leaveOrClose({ roomID: "room", userUID: "user" }),
    {
      ok: true,
      mode: "closed",
      alreadyDeleted: true,
      skipSocketCloseEffects: true
    }
  );
});
