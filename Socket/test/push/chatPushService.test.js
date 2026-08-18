import assert from "node:assert/strict";
import test from "node:test";
import {
  buildChatPushMulticast,
  createChatPushService
} from "../../src/push/chatPushService.js";

test("FCM data payload는 senderEmail을 포함하지 않는다", () => {
  const payload = buildChatPushMulticast({
    roomID: "room",
    roomName: "Room",
    messageID: "message",
    messageType: "Text",
    senderUID: "sender",
    senderNickname: "Sender",
    preview: "hello",
    tokens: ["token"]
  });
  assert.equal(Object.hasOwn(payload.data, "senderEmail"), false);
});

function makeDB({ isBlocked = false, relationError = null } = {}) {
  const relationGet = async () => {
    if (relationError) throw relationError;
    return { exists: isBlocked };
  };
  const memberDoc = {
    id: "recipient",
    data: () => ({ userID: "recipient" })
  };
  const query = {
    orderBy() { return this; },
    limit() { return this; },
    async get() { return { empty: false, size: 1, docs: [memberDoc] }; }
  };
  return {
    collection(name) {
      return {
        doc(id) {
          if (name === "Rooms") {
            return {
              async get() { return { exists: true, data: () => ({ roomName: "room" }) }; },
              collection() { return query; }
            };
          }
          return {
            collection(subcollection) {
              return {
                doc() { return { get: relationGet }; },
                async get() {
                  assert.equal(subcollection, "devices");
                  return { docs: [] };
                }
              };
            }
          };
        }
      };
    }
  };
}

test("blocked sender push is suppressed before device lookup", async () => {
  const logs = [];
  const originalLog = console.log;
  console.log = (...args) => logs.push(args);
  try {
    const service = createChatPushService({
      db: makeDB({ isBlocked: true }),
      admin: {},
      clock: { nowMillis: () => 0 }
    });
    await service.fanoutChatPush({
      roomID: "room",
      messageData: { ID: "message", senderUID: "sender", senderNickname: "sender" }
    });
    assert.equal(logs.at(-1)?.[1]?.skipped?.sender_blocked, 1);
  } finally {
    console.log = originalLog;
  }
});

test("block lookup failure suppresses only that recipient", async () => {
  const logs = [];
  const errors = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => logs.push(args);
  console.error = (...args) => errors.push(args);
  try {
    const service = createChatPushService({
      db: makeDB({ relationError: new Error("offline") }),
      admin: {},
      clock: { nowMillis: () => 0 }
    });
    await service.fanoutChatPush({
      roomID: "room",
      messageData: { ID: "message", senderUID: "sender", senderNickname: "sender" }
    });
    assert.equal(logs.at(-1)?.[1]?.skipped?.block_lookup_failed, 1);
    assert.equal(errors.length, 1);
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
});
