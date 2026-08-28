import assert from "node:assert/strict";
import test from "node:test";

import { createDeletionDeliveryWatcher } from "../../src/deletion/deletionDeliveryWatcher.js";

function memoryFirestore(initial) {
  const values = new Map(Object.entries(initial));
  const snapshot = (ref) => ({
    exists: values.has(ref.path),
    data: () => values.get(ref.path),
    ref
  });
  const reference = (path) => ({
    path,
    id: path.split("/").at(-1)
  });
  const timestampValue = (value) => value && typeof value.toMillis === "function" ?
    value.toMillis() : value;
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

function pendingSingle(overrides = {}) {
  return {
    roomID: "room-a",
    messageID: "message-1",
    seq: 7,
    deletionRevision: 3,
    eventKind: "messageDeleted",
    status: "pending",
    attempt: 0,
    nextAttemptAt: {toMillis: () => 1_000},
    leaseToken: null,
    leaseExpiresAt: null,
    ...overrides
  };
}

function fixture(initial = {
  "chatMessageDeletionDeliveryJobs/single": pendingSingle()
}) {
  const memory = memoryFirestore(initial);
  let nowMillis = 2_000;
  const roomEmits = [];
  const io = {
    to: (roomID) => ({
      emit: (event, payload) => roomEmits.push({roomID, event, payload})
    })
  };
  const watcher = createDeletionDeliveryWatcher({
    db: memory.db,
    admin,
    io,
    clock: {nowMillis: () => nowMillis},
    leaseToken: () => "lease-token",
    logger: {error() {}}
  });
  return {
    ...memory,
    watcher,
    io,
    roomEmits,
    setNow: (value) => { nowMillis = value; }
  };
}

test("단건 삭제 job은 대상 room에 최소 payload를 emit하고 completed가 된다", async () => {
  const target = fixture();

  await target.watcher.drainOnce();

  assert.deepEqual(target.roomEmits, [{
    roomID: "room-a",
    event: "chat:messageDeleted",
    payload: {
      roomID: "room-a",
      messageID: "message-1",
      seq: 7,
      deletionRevision: 3
    }
  }]);
  const completed = target.values.get("chatMessageDeletionDeliveryJobs/single");
  assert.equal(completed.status, "completed");
  assert.equal(completed.attempt, 1);
  assert.equal(completed.leaseToken, null);
  assert.equal(completed.expiresAt.toMillis(), 604_802_000);

  await target.watcher.drainOnce();
  assert.equal(target.roomEmits.length, 1);
});

test("bulk head job은 메시지 배열 없이 해당 room에만 revision 범위를 emit한다", async () => {
  const target = fixture({
    "chatMessageDeletionDeliveryJobs/bulk-a": {
      roomID: "room-a",
      fromRevision: 4,
      toRevision: 8,
      eventKind: "deletionHeadAdvanced",
      status: "pending",
      attempt: 0,
      nextAttemptAt: {toMillis: () => 1_000}
    },
    "chatMessageDeletionDeliveryJobs/bulk-b": {
      roomID: "room-b",
      fromRevision: 10,
      toRevision: 12,
      eventKind: "deletionHeadAdvanced",
      status: "pending",
      attempt: 0,
      nextAttemptAt: {toMillis: () => 1_000}
    }
  });

  await target.watcher.drainOnce();

  assert.deepEqual(target.roomEmits, [
    {
      roomID: "room-a",
      event: "chat:messageDeletionHeadAdvanced",
      payload: {roomID: "room-a", fromRevision: 4, toRevision: 8}
    },
    {
      roomID: "room-b",
      event: "chat:messageDeletionHeadAdvanced",
      payload: {roomID: "room-b", fromRevision: 10, toRevision: 12}
    }
  ]);
  assert.equal("messages" in target.roomEmits[0].payload, false);
});

test("emit 실패는 due retry로 돌아가고 성공 시 같은 revision을 재전달한다", async () => {
  const target = fixture();
  let shouldFail = true;
  target.io.to = (roomID) => ({
    emit(event, payload) {
      if (shouldFail) throw new Error("socket unavailable");
      target.roomEmits.push({roomID, event, payload});
    }
  });

  await target.watcher.drainOnce();
  const retry = target.values.get("chatMessageDeletionDeliveryJobs/single");
  assert.equal(retry.status, "retryPending");
  assert.equal(retry.attempt, 1);
  assert.equal(retry.nextAttemptAt.toMillis(), 4_000);

  shouldFail = false;
  target.setNow(4_000);
  await target.watcher.drainOnce();
  assert.equal(target.roomEmits.length, 1);
  assert.equal(target.roomEmits[0].payload.deletionRevision, 3);
  assert.equal(target.values.get("chatMessageDeletionDeliveryJobs/single").status, "completed");
});

test("만료된 마지막 processing lease는 attempt 증가 없이 회수해 완료한다", async () => {
  const target = fixture({
    "chatMessageDeletionDeliveryJobs/single": pendingSingle({
      status: "processing",
      attempt: 10,
      leaseToken: "dead-worker",
      leaseExpiresAt: {toMillis: () => 1_000}
    })
  });

  await target.watcher.drainOnce();

  assert.equal(target.roomEmits.length, 1);
  const completed = target.values.get("chatMessageDeletionDeliveryJobs/single");
  assert.equal(completed.status, "completed");
  assert.equal(completed.attempt, 10);
});

test("10번째 물리 전달 실패는 failed terminal과 7일 TTL로 끝난다", async () => {
  const target = fixture({
    "chatMessageDeletionDeliveryJobs/single": pendingSingle({
      status: "retryPending",
      attempt: 9
    })
  });
  target.io.to = () => ({emit() { throw new Error("socket unavailable"); }});

  await target.watcher.drainOnce();

  const failed = target.values.get("chatMessageDeletionDeliveryJobs/single");
  assert.equal(failed.status, "failed");
  assert.equal(failed.attempt, 10);
  assert.equal(failed.lastErrorCode, "max_attempts_exceeded");
  assert.equal(failed.nextAttemptAt, null);
  assert.equal(failed.expiresAt.toMillis(), 604_802_000);
});

test("유효한 processing lease와 잘못된 payload는 각각 skip·안전한 retry로 처리한다", async () => {
  const target = fixture({
    "chatMessageDeletionDeliveryJobs/leased": pendingSingle({
      status: "processing",
      attempt: 1,
      leaseExpiresAt: {toMillis: () => 10_000}
    }),
    "chatMessageDeletionDeliveryJobs/invalid": pendingSingle({
      messageID: "",
      attempt: 9
    })
  });

  await target.watcher.drainOnce();

  assert.equal(target.roomEmits.length, 0);
  assert.equal(target.values.get("chatMessageDeletionDeliveryJobs/leased").status, "processing");
  assert.equal(target.values.get("chatMessageDeletionDeliveryJobs/invalid").status, "failed");
});
