import assert from "node:assert/strict";
import test from "node:test";

import { createSequenceStore } from "../../src/messages/sequenceStore.js";

function createDocumentReference(path) {
  return {
    path,
    collection(name) {
      return {
        doc(id) {
          return createDocumentReference(`${path}/${name}/${id}`);
        }
      };
    }
  };
}

function createFirestoreFake(documents) {
  const writes = [];
  const reads = [];
  const db = {
    collection(name) {
      return {
        doc(id) {
          return createDocumentReference(`${name}/${id}`);
        }
      };
    },
    async runTransaction(operation) {
      return operation({
        async get(ref) {
          reads.push(ref.path);
          const data = documents.get(ref.path);
          return {
            exists: data != null,
            data: () => data
          };
        },
        set(ref, data, options) {
          writes.push({ type: "set", path: ref.path, data, options });
        },
        delete(ref) {
          writes.push({ type: "delete", path: ref.path });
        }
      });
    }
  };
  return { db, reads, writes };
}

const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => "server-time"
    }
  }
};

test("신규 message는 next seq와 created true를 반환하고 message/room/reservation을 갱신한다", async () => {
  const documents = new Map([["Rooms/room", { seq: 4 }]]);
  const fixture = createFirestoreFake(documents);
  const mediaUploadRef = createDocumentReference("Rooms/room/MediaUploads/message");
  const store = createSequenceStore({ db: fixture.db, admin });
  const messageData = {
    msg: " hello ",
    attachments: [],
    senderUID: "user"
  };

  const outcome = await store.allocateSeqAndPersist(
    "room",
    "message",
    messageData,
    { mediaUploadRef }
  );

  assert.deepEqual(outcome, { seq: 5, created: true });
  assert.deepEqual(fixture.reads, ["Rooms/room/Messages/message", "Rooms/room"]);
  assert.deepEqual(fixture.writes, [
    {
      type: "set",
      path: "Rooms/room/Messages/message",
      data: { ...messageData, seq: 5 },
      options: { merge: true }
    },
    {
      type: "set",
      path: "Rooms/room",
      data: {
        seq: 5,
        lastMessage: "hello",
        lastMessageAt: "server-time",
        lastMessageSeq: 5
      },
      options: { merge: true }
    },
    {
      type: "delete",
      path: "Rooms/room/MediaUploads/message"
    }
  ]);
});

test("기존 message는 기존 seq와 created false를 반환하고 아무 문서도 다시 쓰지 않는다", async () => {
  const documents = new Map([
    ["Rooms/room", { seq: 10 }],
    ["Rooms/room/Messages/message", { seq: 7, msg: "original" }]
  ]);
  const fixture = createFirestoreFake(documents);
  const store = createSequenceStore({ db: fixture.db, admin });

  const outcome = await store.allocateSeqAndPersist(
    "room",
    "message",
    { msg: "retry payload" },
    { mediaUploadRef: createDocumentReference("Rooms/room/MediaUploads/message") }
  );

  assert.deepEqual(outcome, { seq: 7, created: false });
  assert.deepEqual(fixture.reads, ["Rooms/room/Messages/message"]);
  assert.deepEqual(fixture.writes, []);
});
