import assert from "node:assert/strict";
import test from "node:test";

import {createRoleEventDeliveryWatcher} from "../../src/roles/roleEventDeliveryWatcher.js";

function memoryFirestore(initial) {
  const values = new Map(Object.entries(initial));
  const reference = (path) => ({
    path,
    collection: (name) => collection(`${path}/${name}`),
    get: async () => snapshot(reference(path))
  });
  const snapshot = (ref) => ({exists: values.has(ref.path), data: () => values.get(ref.path), ref});
  const millis = (value) => value && typeof value.toMillis === "function" ? value.toMillis() : value;
  const query = (path, filters = [], ordering = null, maximum = Infinity) => ({
    where: (field, operation, expected) =>
      query(path, [...filters, {field, operation, expected}], ordering, maximum),
    orderBy: (field, direction) => query(path, filters, {field, direction}, maximum),
    limit: (count) => query(path, filters, ordering, count),
    get: async () => {
      let entries = [...values.entries()]
        .filter(([key]) => key.split("/").length === 2 && key.startsWith(`${path}/`))
        .filter(([, value]) => filters.every(({field, operation, expected}) => {
          const actual = millis(value[field]);
          const wanted = millis(expected);
          if (operation === "==") return actual === wanted;
          if (operation === "<=") return actual <= wanted;
          return false;
        }));
      if (ordering) entries.sort((lhs, rhs) => millis(lhs[1][ordering.field]) - millis(rhs[1][ordering.field]));
      return {docs: entries.slice(0, maximum).map(([key]) => snapshot(reference(key)))};
    },
    onSnapshot: () => () => {}
  });
  const collection = (path) => ({
    doc: (id) => reference(`${path}/${id}`),
    where: (field, operation, expected) => query(path).where(field, operation, expected)
  });
  const db = {
    collection,
    runTransaction: async (operation) => operation({
      get: async (ref) => snapshot(ref),
      update: (ref, data) => values.set(ref.path, {...values.get(ref.path), ...data}),
      delete: (ref) => values.delete(ref.path)
    })
  };
  return {db, values};
}

const admin = {firestore: {
  Timestamp: {fromMillis: (value) => ({toMillis: () => value})},
  FieldValue: {serverTimestamp: () => ({serverTimestamp: true})}
}};

function fixture(attempt = 0) {
  const memory = memoryFirestore({
    "chatRoleEventDeliveryJobs/event": {
      roomID: "room", eventID: "event", seq: 7, status: "pending", attempt,
      nextAttemptAt: {toMillis: () => 1_000}, leaseOwner: null, leaseExpiresAt: null
    },
    "Rooms/room/Messages/event": {
      ID: "event", roomID: "room", seq: 7, messageType: "roomRoleEvent",
      serverGenerated: true,
      roleEvent: {kind: "moderatorAssigned", subjectUID: "user", subjectNicknameSnapshot: "사용자"}
    }
  });
  let nowMillis = 2_000;
  const emits = [];
  const io = {to: (roomID) => ({emit: (event, payload) => emits.push({roomID, event, payload})})};
  const watcher = createRoleEventDeliveryWatcher({
    db: memory.db, admin, io, clock: {nowMillis: () => nowMillis},
    leaseOwner: () => "worker", logger: {error() {}}
  });
  return {...memory, watcher, emits, io, setNow: (value) => { nowMillis = value; }};
}

test("canonical role event를 room에 전달하고 성공 job을 즉시 삭제한다", async () => {
  const target = fixture();
  await target.watcher.drainOnce();
  assert.equal(target.emits.length, 1);
  assert.equal(target.emits[0].event, "chat:roomRoleEvent");
  assert.equal(target.emits[0].payload.ID, "event");
  assert.equal(target.values.has("chatRoleEventDeliveryJobs/event"), false);
});

test("전달 실패는 backoff하고 10번째 실패만 24시간 TTL terminal로 남긴다", async () => {
  const target = fixture(8);
  target.io.to = () => ({emit() { throw new Error("socket unavailable"); }});
  await target.watcher.drainOnce();
  const retry = target.values.get("chatRoleEventDeliveryJobs/event");
  assert.equal(retry.status, "retryPending");
  assert.equal(retry.attempt, 9);
  assert.equal(retry.expiresAt, null);

  retry.status = "pending";
  retry.nextAttemptAt = {toMillis: () => 1_000};
  await target.watcher.drainOnce();
  const failed = target.values.get("chatRoleEventDeliveryJobs/event");
  assert.equal(failed.status, "failed");
  assert.equal(failed.attempt, 10);
  assert.equal(failed.expiresAt.toMillis(), 2_000 + 24 * 60 * 60 * 1_000);
});

test("canonical event가 아니면 전송하지 않고 재시도한다", async () => {
  const target = fixture();
  target.values.get("Rooms/room/Messages/event").serverGenerated = false;
  await target.watcher.drainOnce();
  assert.equal(target.emits.length, 0);
  assert.equal(target.values.get("chatRoleEventDeliveryJobs/event").status, "retryPending");
});
