import assert from "node:assert/strict";
import test from "node:test";

import { createMediaDeliveryWatcher } from "../../src/media/mediaDeliveryWatcher.js";

function memoryFirestore(initial) {
  const values = new Map(Object.entries(initial));
  const snapshot = (ref) => ({
    exists: values.has(ref.path),
    data: () => values.get(ref.path),
    ref
  });
  const reference = (path) => ({
    path,
    id: path.split("/").at(-1),
    collection: (name) => collection(`${path}/${name}`),
    get: async () => snapshot(reference(path))
  });
  const timestampValue = (value) => value && typeof value.toMillis === "function"
    ? value.toMillis()
    : value;
  const query = (path, filters = [], ordering = null, maximum = Infinity) => ({
    where: (field, operation, expected) =>
      query(path, [...filters, {field, operation, expected}], ordering, maximum),
    orderBy: (field, direction) => query(path, filters, {field, direction}, maximum),
    limit: (count) => query(path, filters, ordering, count),
    get: async () => {
      let entries = [...values.entries()]
        .filter(([key]) => key.split("/").length === 2 && key.startsWith(`${path}/`))
        .filter(([, value]) => filters.every(({field, operation, expected}) => {
          const actualValue = timestampValue(value[field]);
          const expectedValue = timestampValue(expected);
          if (operation === "==") return actualValue === expectedValue;
          if (operation === "<=") return actualValue <= expectedValue;
          return false;
        }));
      if (ordering) {
        entries.sort((lhs, rhs) => {
          const difference = timestampValue(lhs[1][ordering.field]) -
            timestampValue(rhs[1][ordering.field]);
          return ordering.direction === "desc" ? -difference : difference;
        });
      }
      return {docs: entries.slice(0, maximum).map(([key]) => snapshot(reference(key)))};
    },
    onSnapshot: () => () => {}
  });
  const collection = (path) => ({
    doc: (id) => reference(`${path}/${id}`),
    where: (field, operation, expected) =>
      query(path).where(field, operation, expected)
  });
  const db = {
    collection,
    runTransaction: async (operation) => operation({
      get: async (ref) => snapshot(ref),
      update: (ref, data) => values.set(ref.path, {...values.get(ref.path), ...data})
    })
  };
  return { db, values };
}

const admin = {
  firestore: {
    Timestamp: { fromMillis: (milliseconds) => ({toMillis: () => milliseconds}) },
    FieldValue: { serverTimestamp: () => ({serverTimestamp: true}) }
  }
};

function fixture() {
  const memory = memoryFirestore({
    "chatMediaDeliveryJobs/room_message": {
      roomID: "room",
      messageID: "message",
      seq: 7,
      eventKind: "receiveImages",
      status: "pending",
      attempt: 0,
      nextAttemptAt: {toMillis: () => 1_000}
    },
    "Rooms/room/Messages/message": {
      ID: "message",
      roomID: "room",
      senderUID: "sender",
      senderNickname: "아웃픽",
      messageType: "Image",
      moderationVisibilityState: "visible",
      isDeleted: false,
      seq: 7,
      attachments: []
    }
  });
  let nowMillis = 2_000;
  const roomEmits = [];
  const senderEmits = [];
  const io = {
    to: (roomID) => ({
      emit: (event, payload) => roomEmits.push({roomID, event, payload})
    }),
    sockets: {sockets: new Map([["socket", {
      userUID: "sender",
      emit: (event, payload) => senderEmits.push({event, payload})
    }]])}
  };
  const pushes = [];
  const watcher = createMediaDeliveryWatcher({
    db: memory.db,
    admin,
    io,
    clock: {nowMillis: () => nowMillis},
    fanoutChatPush: async (payload) => pushes.push(payload),
    leaseToken: () => "lease",
    logger: {error() {}}
  });
  return {
    ...memory,
    watcher,
    roomEmits,
    senderEmits,
    pushes,
    setNow: (value) => { nowMillis = value; },
    io
  };
}

test("pending delivery는 lease 후 기존 media event와 push를 보내고 completed가 된다", async () => {
  const target = fixture();
  await target.watcher.drainOnce();

  assert.equal(target.roomEmits.length, 1);
  assert.equal(target.roomEmits[0].event, "receiveImages");
  assert.equal(target.pushes.length, 1);
  assert.equal(target.senderEmits[0].event, "chat:mediaProcessingStatusChanged");
  assert.equal(target.values.get("chatMediaDeliveryJobs/room_message").status, "completed");

  await target.watcher.drainOnce();
  assert.equal(target.roomEmits.length, 1);
});

test("emit 실패는 retryPending으로 돌리고 due 이후 같은 messageID/seq를 재전달한다", async () => {
  const target = fixture();
  let shouldFail = true;
  target.io.to = (roomID) => ({
    emit(event, payload) {
      if (shouldFail) throw new Error("socket unavailable");
      target.roomEmits.push({roomID, event, payload});
    }
  });

  await target.watcher.drainOnce();
  assert.equal(target.values.get("chatMediaDeliveryJobs/room_message").status, "retryPending");
  assert.equal(target.pushes.length, 0);

  shouldFail = false;
  target.setNow(10_000);
  await target.watcher.drainOnce();
  assert.equal(target.roomEmits.length, 1);
  assert.equal(target.roomEmits[0].payload.seq, 7);
  assert.equal(target.values.get("chatMediaDeliveryJobs/room_message").status, "completed");
});

test("미도래 retry가 있어도 due pending 전달을 막지 않는다", async () => {
  const target = fixture();
  for (let index = 0; index < 60; index += 1) {
    target.values.set(`chatMediaDeliveryJobs/future_${index}`, {
      roomID: "room",
      messageID: `future-${index}`,
      seq: 100 + index,
      eventKind: "receiveImages",
      status: "retryPending",
      attempt: 1,
      nextAttemptAt: {toMillis: () => 60_000}
    });
  }

  await target.watcher.drainOnce();

  assert.equal(target.roomEmits.length, 1);
  assert.equal(target.roomEmits[0].payload.ID, "message");
  assert.equal(target.values.get("chatMediaDeliveryJobs/room_message").status, "completed");
});
