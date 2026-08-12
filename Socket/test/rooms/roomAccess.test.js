import assert from "node:assert/strict";
import test from "node:test";

import { createRoomAccess } from "../../src/rooms/roomAccess.js";

function document(exists, data = {}) {
  return { exists, data: () => data };
}

test("canonical principal의 활성 밴은 잔존 member보다 우선해 쓰기 접근을 거부한다", async () => {
  const room = document(true, { isClosed: false, lifecycleStatus: "active" });
  const db = {
    collection(name) {
      if (name === "moderationAccounts") {
        return { doc: () => ({ get: async () => document(true, {
          moderationPrincipalID: "principal-user"
        }) }) };
      }
      assert.equal(name, "Rooms");
      return { doc: () => ({
        get: async () => room,
        collection: (child) => ({
          doc: () => ({ get: async () => child === "bans" ?
            document(true, { isActive: true }) : document(true, { role: "member" }) })
        })
      }) };
    }
  };
  const result = await createRoomAccess({ db }).loadRoomAccess("room-1", "user-1");
  assert.deepEqual(result, { ok: false, error: "room_banned" });
});
