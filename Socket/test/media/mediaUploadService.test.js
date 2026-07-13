import assert from "node:assert/strict";
import test from "node:test";

import {
  createMediaUploadService,
  normalizeMediaKind,
  validateMediaUploadContract
} from "../../src/media/mediaUploadService.js";

test("media kind와 image/video path count 계약을 유지한다", () => {
  assert.equal(normalizeMediaKind("image"), "images");
  assert.equal(normalizeMediaKind("images"), "images");
  assert.equal(normalizeMediaKind("video"), "video");
  assert.equal(normalizeMediaKind("audio"), "");

  assert.deepEqual(validateMediaUploadContract("images", 2, 4), {
    ok: true, attachmentCount: 2, expectedPathCount: 4
  });
  assert.equal(validateMediaUploadContract("images", 31, 62).error, "invalid_attachment_count");
  assert.equal(validateMediaUploadContract("video", 1, 1).error, "invalid_expected_path_count");
});

function createDocumentDB({ reservation, message, writes }) {
  return {
    collection(collectionName) {
      assert.equal(collectionName, "Rooms");
      return {
        doc(roomID) {
          return {
            collection(subcollection) {
              return {
                doc(messageID) {
                  const value = subcollection === "MediaUploads" ? reservation : message;
                  return {
                    roomID,
                    messageID,
                    get: async () => ({
                      exists: value != null,
                      data: () => value
                    }),
                    set: async (data, options) => writes.push({ subcollection, data, options })
                  };
                }
              };
            }
          };
        }
      };
    }
  };
}

const admin = {
  firestore: {
    FieldValue: { serverTimestamp: () => "server-time" },
    Timestamp: { fromDate: (date) => ({ date }) }
  }
};

test("preflight는 신규 pending reservation field와 24시간 TTL을 유지한다", async () => {
  const writes = [];
  const service = createMediaUploadService({
    db: createDocumentDB({ reservation: null, message: null, writes }),
    admin,
    clock: { nowMillis: () => 1_000 }
  });
  const result = await service.preflight({
    roomID: "room",
    messageID: "message",
    senderUID: "user",
    senderEmail: "user@example.com",
    kind: "images",
    contract: { attachmentCount: 2, expectedPathCount: 4 }
  });

  assert.deepEqual(result, {
    ok: true,
    status: "pending",
    messageID: "message",
    storagePrefix: "rooms/room/messages/message",
    attachmentCount: 2,
    expectedPathCount: 4
  });
  assert.equal(writes.length, 1);
  assert.equal(writes[0].data.storagePrefix, "rooms/room/messages/message");
  assert.equal(writes[0].data.expiresAt.date.getTime(), 86_401_000);
});

test("reservation sender/kind/path/prefix/expiry 검증을 유지한다", async () => {
  const base = {
    status: "pending",
    senderUID: "user",
    kind: "video",
    attachmentCount: 1,
    expectedPathCount: 2,
    storagePrefix: "rooms/room/messages/message",
    expiresAt: { toMillis: () => 2_000 }
  };
  const makeService = (reservation, now = 1_000) => createMediaUploadService({
    db: createDocumentDB({ reservation, message: null, writes: [] }),
    admin,
    clock: { nowMillis: () => now }
  });
  const input = {
    roomID: "room",
    messageID: "message",
    senderUID: "user",
    kind: "video",
    attachmentCount: 1,
    expectedPathCount: 2,
    storagePaths: [
      "rooms/room/messages/message/video.mp4",
      "rooms/room/messages/message/thumb.jpg"
    ]
  };

  assert.equal((await makeService(base).assertReservation(input)).ok, true);
  assert.equal((await makeService({ ...base, senderUID: "other" })
    .assertReservation(input)).error, "media_reservation_sender_mismatch");
  assert.equal((await makeService(base, 2_000)
    .assertReservation(input)).error, "media_reservation_expired");
  assert.equal((await makeService(base).assertReservation({
    ...input,
    storagePaths: ["outside/video.mp4", "outside/thumb.jpg"]
  })).error, "media_reservation_prefix_mismatch");
});
