/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {type Firestore} from "firebase-admin/firestore";
import {publishCompletedMediaUpload} from "./readyService.js";
import {completeSynchronousImageExecution} from "./orchestrationService.js";

function memoryFirestore(initial: Record<string, Record<string, unknown>>) {
  const values = new Map(Object.entries(initial));
  const reference = (path: string): Record<string, unknown> => ({
    path,
    id: path.split("/").at(-1),
    collection: (name: string) => collection(`${path}/${name}`),
    get: async () => snapshot({path}),
  });
  const collection = (path: string): Record<string, unknown> => ({
    doc: (id: string) => reference(`${path}/${id}`),
  });
  const snapshot = (ref: {path: string}) => {
    const data = values.get(ref.path);
    return {exists: data !== undefined, data: () => data, ref};
  };
  const firestore = {
    collection,
    runTransaction: async (operation: (transaction: Record<string, unknown>) => unknown) => {
      const transaction = {
        get: async (ref: {path: string}) => snapshot(ref),
        create: (ref: {path: string}, data: Record<string, unknown>) => {
          if (values.has(ref.path)) throw new Error("already_exists");
          values.set(ref.path, {...data});
        },
        set: (ref: {path: string}, data: Record<string, unknown>, options?: {merge?: boolean}) => {
          values.set(ref.path, options?.merge ? {...(values.get(ref.path) ?? {}), ...data} : {...data});
        },
        update: (ref: {path: string}, data: Record<string, unknown>) => {
          values.set(ref.path, {...(values.get(ref.path) ?? {}), ...data});
        },
      };
      return operation(transaction);
    },
  } as unknown as Firestore;
  return {firestore, values, reference};
}

function fixture(overrides: Record<string, Record<string, unknown>> = {}) {
  const uploadPath = "Rooms/room/MediaUploads/message";
  const attachmentID = "attachment";
  const manifest = [{
    attachmentID,
    displayBucket: "ready",
    displayPath: `rooms/room/messages/message/attachments/${attachmentID}/display`,
    displayGeneration: "1",
    displayBytes: 123,
    displayContentType: "image/jpeg",
    thumbnailBucket: "ready",
    thumbnailPath: `rooms/room/messages/message/attachments/${attachmentID}/thumbnail`,
    thumbnailGeneration: "2",
    thumbnailBytes: 45,
    thumbnailContentType: "image/jpeg",
  }];
  const memory = memoryFirestore({
    [uploadPath]: {
      contractVersion: 2,
      roomID: "room",
      uploadID: "message",
      messageID: "message",
      kind: "images",
      processingStatus: "processing",
      leaseToken: "lease",
      processingSlotID: "image-0",
      principalSlotID: "principal_images_0",
      quarantineBucket: "quarantine",
      quarantinePaths: ["room/source"],
      attachmentCount: 1,
      normalizedManifest: manifest,
    },
    "Rooms/room": {seq: 4},
    "chatMediaProcessingSlots/image-0": {leaseToken: "lease"},
    "chatMediaPrincipalUploadSlots/principal_images_0": {
      ownerUploadPath: uploadPath,
    },
    ...overrides,
  });
  return {memory, uploadPath, manifest};
}

test("v2 worker 결과는 메시지로 확정하지 않고 실패·객체 정리 상태로 돌린다", async () => {
  const {memory, uploadPath, manifest} = fixture();
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, false);
  assert.equal(result.reason, "legacy_media_contract_disabled");
  assert.deepEqual(result.readyObjects, [
    {bucket: "ready", path: manifest[0].displayPath},
    {bucket: "ready", path: manifest[0].thumbnailPath},
  ]);
  assert.equal(memory.values.has("Rooms/room/Messages/message"), false);
  assert.equal(memory.values.get("Rooms/room")?.seq, 4);
  assert.equal(memory.values.get("chatMediaDeliveryJobs/room_message"), undefined);
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "failed");
  assert.equal(memory.values.get(uploadPath)?.failureCode, "legacy_media_contract_disabled");
  assert.equal(memory.values.get("chatMediaProcessingSlots/image-0")?.leaseToken, null);
  assert.equal(memory.values.get("chatMediaPrincipalUploadSlots/principal_images_0")?.ownerUploadPath, null);
});

test("legacy image completion은 slot을 반환하지만 message/seq를 만들지 않는다", async () => {
  const {memory, uploadPath} = fixture();
  await completeSynchronousImageExecution({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    leaseToken: "lease",
    slotID: "image-0",
    nowMillis: 10_000,
  });

  assert.equal(memory.values.has("Rooms/room/Messages/message"), false);
  assert.equal(memory.values.get("Rooms/room")?.seq, 4);
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "failed");
  assert.equal(memory.values.get("chatMediaProcessingSlots/image-0")?.leaseToken, null);
});

test("오래된 lease 결과는 현재 reservation을 실패 처리하거나 slot을 반환하지 않는다", async () => {
  const {memory, uploadPath} = fixture();
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
    expectedLeaseToken: "old",
  });

  assert.equal(result.reason, "stale_execution");
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "processing");
  assert.equal(memory.values.get("chatMediaProcessingSlots/image-0")?.leaseToken, "lease");
  assert.equal(memory.values.has("Rooms/room/Messages/message"), false);
});

test("이미 terminal인 v2 결과도 성공 ACK나 메시지 duplicate로 노출되지 않는다", async () => {
  const {memory, uploadPath} = fixture({
    ["Rooms/room/MediaUploads/message"]: {
      contractVersion: 2,
      roomID: "room",
      messageID: "message",
      kind: "images",
      processingStatus: "ready",
      seq: 5,
      normalizedManifest: [],
    },
    ["Rooms/room/Messages/message"]: {ID: "message", seq: 5},
  });
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, false);
  assert.equal(result.duplicate, false);
  assert.equal(result.reason, "legacy_media_contract_disabled");
});

test("contract 3 직접 업로드 원장은 legacy worker publisher에서 처리하지 않는다", async () => {
  const {memory, uploadPath} = fixture({
    ["Rooms/room/MediaUploads/message"]: {
      contractVersion: 3,
      roomID: "room",
      messageID: "message",
      kind: "images",
      processingStatus: "processing",
    },
  });
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, false);
  assert.equal(result.reason, "invalid_contract");
  assert.equal(memory.values.has("Rooms/room/Messages/message"), false);
});
