import assert from "node:assert/strict";
import test from "node:test";

import {
  createMediaUploadService,
  normalizeMediaKind,
  validateExistingMediaMessage,
  validateExistingMediaPreflight,
  validateMediaUploadContract,
  validateMediaUploadContractV2,
  validateMediaSourceDescriptors
} from "../../src/media/mediaUploadService.js";

const SOURCE_SHA256 = "a".repeat(64);
const sourceDescriptors = (kind, count) => Array.from({length: count}, (_, index) => ({
  index,
  contentType: kind === "video" ? "video/mp4" : "image/jpeg",
  sizeBytes: 1024,
  sha256: SOURCE_SHA256
}));
const signedUploadDependencies = () => ({
  createQuarantineSignedUploadTarget: async ({path, contentType}) => ({
    signedURL: `https://upload.test/${path}`,
    requiredHeaders: {"content-type": contentType}
  })
});

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
  assert.deepEqual(validateMediaUploadContractV2("images", 2, 2), {
    ok: true, attachmentCount: 2, expectedPathCount: 2
  });
  assert.deepEqual(validateMediaUploadContractV2("video", 1, 1), {
    ok: true, attachmentCount: 1, expectedPathCount: 1
  });
  assert.equal(validateMediaUploadContractV2("images", 2, 4).error,
    "invalid_expected_path_count");
  assert.equal(validateMediaSourceDescriptors(
    "images",
    {attachmentCount: 2},
    sourceDescriptors("images", 2)
  ).ok, true);
  assert.equal(validateMediaSourceDescriptors(
    "images",
    {attachmentCount: 1},
    [{...sourceDescriptors("images", 1)[0], sizeBytes: 16 * 1024 * 1024}]
  ).error, "media_source_invalid");
});

test("350 MiB 영상은 단일 source로 허용하고 상한 초과는 거부한다", () => {
  const totalBytes = 350 * 1024 * 1024;
  const result = validateMediaSourceDescriptors("video", {attachmentCount: 1}, [{
    index: 0,
    contentType: "video/mp4",
    sizeBytes: totalBytes,
    sha256: SOURCE_SHA256
  }]);
  assert.equal(result.ok, true);
  assert.equal(validateMediaSourceDescriptors("video", {attachmentCount: 1}, [{
    index: 0,
    contentType: "video/mp4",
    sizeBytes: totalBytes + 1,
    sha256: SOURCE_SHA256
  }]).error, "media_source_invalid");
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
    Timestamp: { fromDate: (date) => ({ date, toMillis: () => date.getTime() }) }
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

test("완료된 media retry는 sender/kind/path가 모두 일치할 때만 기존 seq를 반환한다", () => {
  const existingMessage = {
    seq: 12,
    senderUID: "user",
    messageType: "Image",
    attachments: [{
      pathThumb: "rooms/room/messages/message/thumb.jpg",
      pathOriginal: "rooms/room/messages/message/original.jpg"
    }]
  };
  const input = {
    existingMessage,
    senderUID: "user",
    kind: "images",
    storagePaths: [
      "rooms/room/messages/message/original.jpg",
      "rooms/room/messages/message/thumb.jpg"
    ]
  };

  assert.deepEqual(validateExistingMediaMessage(input), {
    ok: true,
    exists: true,
    seq: 12
  });
  assert.equal(validateExistingMediaMessage({
    ...input,
    senderUID: "other"
  }).error, "media_message_conflict");
  assert.equal(validateExistingMediaMessage({
    ...input,
    kind: "video"
  }).error, "media_message_conflict");
  assert.equal(validateExistingMediaMessage({
    ...input,
    storagePaths: ["other/thumb.jpg", "other/original.jpg"]
  }).error, "media_message_conflict");
});

test("완료된 media preflight는 sender/kind/count가 일치할 때만 duplicate로 인정한다", () => {
  const existingMessage = {
    seq: 12,
    senderUID: "user",
    messageType: "Video",
    attachments: [{
      pathThumb: "rooms/room/messages/message/thumb.jpg",
      pathOriginal: "rooms/room/messages/message/video.mp4"
    }]
  };
  const input = {
    existingMessage,
    senderUID: "user",
    kind: "video",
    contract: { attachmentCount: 1, expectedPathCount: 2 }
  };

  assert.deepEqual(validateExistingMediaPreflight(input), {
    ok: true,
    exists: true,
    seq: 12
  });
  assert.equal(validateExistingMediaPreflight({
    ...input,
    senderUID: "other"
  }).error, "media_message_conflict");
  assert.equal(validateExistingMediaPreflight({
    ...input,
    kind: "images"
  }).error, "media_message_conflict");
  assert.equal(validateExistingMediaPreflight({
    ...input,
    contract: { attachmentCount: 2, expectedPathCount: 4 }
  }).error, "media_message_conflict");
});

function createMemoryDB() {
  const values = new Map();
  const writes = [];
  const reference = (path) => ({
    path,
    id: path.split("/").at(-1),
    collection(name) {
      return collection(`${path}/${name}`);
    },
    async get() {
      const value = values.get(path);
      return { exists: value != null, data: () => value, ref: this };
    },
    async set(data, options) {
      const next = options?.merge ? { ...(values.get(path) || {}), ...data } : { ...data };
      values.set(path, next);
      writes.push({ path, operation: "set", data });
    }
  });
  const collection = (path) => ({
    doc(id) { return reference(`${path}/${id}`); }
  });
  const db = {
    collection,
    async runTransaction(operation) {
      const transaction = {
        get: (ref) => ref.get(),
        set(ref, data, options) {
          const next = options?.merge
            ? { ...(values.get(ref.path) || {}), ...data }
            : { ...data };
          values.set(ref.path, next);
          writes.push({ path: ref.path, operation: "set", data });
        },
        update(ref, data) {
          values.set(ref.path, { ...(values.get(ref.path) || {}), ...data });
          writes.push({ path: ref.path, operation: "update", data });
        }
      };
      return operation(transaction);
    }
  };
  return { db, values, writes };
}

test("v2 preflight는 attachment당 source 하나와 principal 동시 slot을 멱등 예약한다", async () => {
  const memory = createMemoryDB();
  const service = createMediaUploadService({
    db: memory.db,
    admin,
    clock: { nowMillis: () => 1_000 },
    quarantineBucketName: "quarantine-bucket",
    loadQuarantineObject: async () => null,
    deleteQuarantineObject: async () => {},
    ...signedUploadDependencies()
  });
  const input = {
    roomID: "room",
    clientMutationID: "mutation-a",
    senderUID: "user",
    moderationPrincipalID: "principal",
    kind: "images",
    contract: { attachmentCount: 2, expectedPathCount: 2 },
    sources: sourceDescriptors("images", 2)
  };
  const first = await service.preflightV2({ ...input, uploadID: "upload-a" });
  const duplicate = await service.preflightV2({ ...input, uploadID: "upload-a" });
  const conflictingReplay = await service.preflightV2({
    ...input, uploadID: "upload-replay"
  });
  const second = await service.preflightV2({
    ...input, uploadID: "upload-b", clientMutationID: "mutation-b"
  });
  const limited = await service.preflightV2({
    ...input, uploadID: "upload-c", clientMutationID: "mutation-c"
  });

  assert.equal(first.ok, true);
  assert.equal(first.quarantinePaths.length, 2);
  assert.equal(first.quarantinePaths.every((path) => path.endsWith("/source")), true);
  assert.equal(first.uploads.length, 2);
  assert.equal(first.uploads.every((upload) => upload.signedURL.startsWith("https://upload.test/")), true);
  assert.equal(duplicate.duplicate, true);
  assert.deepEqual(conflictingReplay, {
    ok: false, error: "media_client_mutation_conflict"
  });
  assert.equal(second.ok, true);
  assert.deepEqual(limited, { ok: false, error: "active_upload_limit" });
  const reservation = memory.values.get("Rooms/room/MediaUploads/upload-a");
  assert.equal(reservation.contractVersion, 2);
  assert.equal(reservation.processingStatus, "uploading");
  assert.equal(reservation.uploadExpiresAt.date.getTime(), 86_401_000);
  assert.equal(reservation.processingDeadlineAt, null);
});

test("v2 finalize는 exact generation/size/MIME manifest만 queued로 전환한다", async () => {
  const memory = createMemoryDB();
  const metadata = new Map();
  const service = createMediaUploadService({
    db: memory.db,
    admin,
    clock: { nowMillis: () => 1_000 },
    quarantineBucketName: "quarantine-bucket",
    loadQuarantineObject: async (path) => {
      const value = metadata.get(path);
      if (!value) throw Object.assign(new Error("not found"), {code: 404});
      return value;
    },
    deleteQuarantineObject: async () => {},
    createQuarantineSignedUploadTarget: signedUploadDependencies()
      .createQuarantineSignedUploadTarget
  });
  const preflight = await service.preflightV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal",
    kind: "video",
    contract: { attachmentCount: 1, expectedPathCount: 1 },
    sources: sourceDescriptors("video", 1)
  });
  metadata.set(preflight.uploads[0].path, {
    generation: "7",
    sizeBytes: 1024,
    contentType: "video/mp4",
    metadata: {
      attachmentID: preflight.attachmentIDs[0],
      sha256: SOURCE_SHA256
    }
  });
  const result = await service.finalizeV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal"
  });
  const duplicate = await service.finalizeV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal"
  });

  assert.equal(result.processingStatus, "queued");
  assert.equal(result.messageID, null);
  assert.equal(result.seq, null);
  assert.equal(duplicate.duplicate, true);
  assert.equal(memory.values.get("Rooms/room/MediaUploads/upload").processingStatus, "queued");
});

test("signed PUT 응답 유실은 Storage 객체 metadata로 완료 복구한다", async () => {
  const memory = createMemoryDB();
  const metadata = new Map();
  const service = createMediaUploadService({
    db: memory.db,
    admin,
    clock: {nowMillis: () => 1_000},
    quarantineBucketName: "quarantine-bucket",
    loadQuarantineObject: async (path) => metadata.get(path) || null,
    deleteQuarantineObject: async () => {},
    ...signedUploadDependencies()
  });
  const input = {
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal",
    kind: "images",
    contract: {attachmentCount: 1, expectedPathCount: 1},
    sources: sourceDescriptors("images", 1)
  };
  const preflight = await service.preflightV2(input);
  const target = preflight.uploads[0];
  metadata.set(target.path, {
    generation: "11",
    sizeBytes: target.sizeBytes,
    contentType: target.contentType,
    metadata: {
      "attachment-id": target.attachmentID,
      sha256: SOURCE_SHA256
    }
  });
  const recovered = await service.refreshUploadTargetsV2(input);
  assert.equal(recovered.uploads.length, 0);
  assert.equal(recovered.completedParts.length, 1);
  assert.equal(recovered.completedParts[0].generation, "11");

  metadata.get(target.path).metadata.sha256 = "b".repeat(64);
  assert.equal((await service.refreshUploadTargetsV2(input)).error,
    "media_upload_source_conflict");
});

test("v2 cancel은 terminal을 먼저 기록하고 source와 principal slot을 정리한다", async () => {
  const memory = createMemoryDB();
  const deleted = [];
  const service = createMediaUploadService({
    db: memory.db,
    admin,
    clock: { nowMillis: () => 1_000 },
    quarantineBucketName: "quarantine-bucket",
    loadQuarantineObject: async () => null,
    deleteQuarantineObject: async (path) => { deleted.push(path); },
    ...signedUploadDependencies()
  });
  const preflight = await service.preflightV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal",
    kind: "images",
    contract: { attachmentCount: 1, expectedPathCount: 1 },
    sources: sourceDescriptors("images", 1)
  });
  const result = await service.cancelV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal"
  });

  assert.equal(result.processingStatus, "canceled");
  assert.deepEqual(deleted, preflight.quarantinePaths);
  const reservation = memory.values.get("Rooms/room/MediaUploads/upload");
  assert.equal(reservation.cleanupStatus, "completed");
  assert.equal(reservation.expiresAt.date.getTime(), 604_801_000);
  const slot = memory.values.get(reservation.principalSlotID);
  assert.equal(slot, undefined);
  const slotValue = memory.values.get(`chatMediaPrincipalUploadSlots/${reservation.principalSlotID}`);
  assert.equal(slotValue.ownerUploadPath, null);
});

test("worker 결과 기록 뒤 cancel은 source 삭제 후 orphan ready cleanup을 pending으로 남긴다", async () => {
  const memory = createMemoryDB();
  const service = createMediaUploadService({
    db: memory.db,
    admin,
    clock: { nowMillis: () => 1_000 },
    quarantineBucketName: "quarantine-bucket",
    loadQuarantineObject: async () => null,
    deleteQuarantineObject: async () => {},
    ...signedUploadDependencies()
  });
  await service.preflightV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal",
    kind: "images",
    contract: { attachmentCount: 1, expectedPathCount: 1 },
    sources: sourceDescriptors("images", 1)
  });
  const path = "Rooms/room/MediaUploads/upload";
  memory.values.set(path, {
    ...memory.values.get(path),
    processingStatus: "processing",
    normalizedManifest: [{displayPath: "ready/display", thumbnailPath: "ready/thumb"}]
  });

  await service.cancelV2({
    roomID: "room",
    uploadID: "upload",
    clientMutationID: "mutation",
    senderUID: "user",
    moderationPrincipalID: "principal"
  });

  assert.equal(memory.values.get(path).processingStatus, "canceled");
  assert.equal(memory.values.get(path).cleanupStatus, "pending");
});
