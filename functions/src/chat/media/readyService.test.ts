/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {publishCompletedMediaUpload} from "./readyService.js";

function memoryFirestore(initial: Record<string, Record<string, unknown>>) {
  const values = new Map(Object.entries(initial));
  const reference = (path: string): Record<string, unknown> => ({
    path,
    id: path.split("/").at(-1),
    collection: (name: string) => collection(`${path}/${name}`),
  });
  const collection = (path: string): Record<string, unknown> => ({
    doc: (id: string) => reference(`${path}/${id}`),
  });
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
  const snapshot = (ref: {path: string}) => {
    const data = values.get(ref.path);
    return {exists: data !== undefined, data: () => data, ref};
  };
  return {firestore, values, reference};
}

function fixture(overrides: Record<string, Record<string, unknown>> = {}) {
  const uploadPath = "Rooms/room/MediaUploads/message";
  const attachmentID = "attachment";
  const initial = {
    [uploadPath]: {
      contractVersion: 2,
      roomID: "room",
      uploadID: "message",
      messageID: "message",
      senderUID: "sender",
      moderationPrincipalID: "principal",
      kind: "images",
      attachmentCount: 1,
      attachmentIDs: [attachmentID],
      quarantineBucket: "quarantine",
      quarantinePaths: ["room/sender/message/attachment/source"],
      processingStatus: "processing",
      leaseToken: "lease",
      processingSlotID: "image-0",
      principalSlotID: "principal_images_0",
      normalizedManifest: [{
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
      }],
      technicalValidationResult: [{
        attachmentID,
        actualFormat: "jpeg",
        width: 1200,
        height: 800,
        frameCount: 1,
        animated: false,
      }],
    },
    "Rooms/room": {seq: 4, isClosed: false, lifecycleStatus: "active"},
    "Rooms/room/members/sender": {userID: "sender"},
    "userPublicProfiles/sender": {nickname: "아웃픽", avatarThumbPath: "profile/thumb"},
    "chatMediaProcessingSlots/image-0": {leaseToken: "lease"},
    "chatMediaPrincipalUploadSlots/principal_images_0": {ownerUploadPath: uploadPath},
    ...overrides,
  };
  const memory = memoryFirestore(initial);
  return {memory, uploadPath};
}

test("worker 완료는 message/seq/index/preview/delivery/ready와 slot 반환을 한 transaction에 반영한다", async () => {
  const {memory, uploadPath} = fixture();
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, true);
  assert.equal(result.seq, 5);
  assert.equal(memory.values.get("Rooms/room")?.seq, 5);
  assert.equal(memory.values.get("Rooms/room/Messages/message")?.seq, 5);
  const message = memory.values.get("Rooms/room/Messages/message");
  assert.equal(message?.unreadMessageSeq, 5);
  assert.equal(memory.values.get("Rooms/room")?.unreadMessageSeq, 5);
  const attachment = (message?.attachments as Array<Record<string, unknown>>)[0];
  assert.equal(attachment.bucketOriginal, "ready");
  assert.equal(attachment.bucketThumb, "ready");
  assert.equal(attachment.generationOriginal, "1");
  assert.equal(attachment.contentTypeOriginal, "image/jpeg");
  assert.equal(attachment.mediaFormat, "jpeg");
  assert.equal(attachment.animated, false);
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.seq, 5);
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.bucketOriginal, "ready");
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.generationOriginal, "1");
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.contentTypeOriginal, "image/jpeg");
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.mediaFormat, "jpeg");
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.animated, false);
  assert.equal(memory.values.get("chatMediaDeliveryJobs/room_message")?.status, "pending");
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "ready");
  assert.equal(memory.values.get("chatMediaProcessingSlots/image-0")?.leaseToken, null);
  assert.equal(memory.values.get("chatMediaPrincipalUploadSlots/principal_images_0")?.ownerUploadPath, null);
  assert.ok(memory.values.get(uploadPath)?.expiresAt instanceof Timestamp);

  const duplicate = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 11_000,
  });
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.seq, 5);
  assert.equal(memory.values.get("Rooms/room")?.seq, 5);
});

test("animated GIF의 검증된 format과 animation metadata를 message와 media index에 보존한다", async () => {
  const seed = fixture();
  const baseUpload = seed.memory.values.get(seed.uploadPath) ?? {};
  const attachmentID = "attachment";
  const {memory, uploadPath} = fixture({
    [seed.uploadPath]: {
      ...baseUpload,
      normalizedManifest: [{
        attachmentID,
        displayBucket: "ready",
        displayPath: `rooms/room/messages/message/attachments/${attachmentID}/display`,
        displayGeneration: "3",
        displayBytes: 3959,
        displayContentType: "image/gif",
        thumbnailBucket: "ready",
        thumbnailPath: `rooms/room/messages/message/attachments/${attachmentID}/thumbnail`,
        thumbnailGeneration: "4",
        thumbnailBytes: 1093,
        thumbnailContentType: "image/jpeg",
      }],
      technicalValidationResult: [{
        attachmentID,
        actualFormat: "gif",
        width: 800,
        height: 800,
        frameCount: 50,
        animated: true,
      }],
    },
  });

  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, true);
  const message = memory.values.get("Rooms/room/Messages/message");
  const attachment = (message?.attachments as Array<Record<string, unknown>>)[0];
  assert.equal(attachment.mediaFormat, "gif");
  assert.equal(attachment.animated, true);
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.mediaFormat, "gif");
  assert.equal(memory.values.get("Rooms/room/mediaIndex/message_0")?.animated, true);
});

test("cancel이 먼저 terminal을 확정하면 message와 seq를 만들지 않고 orphan cleanup 대상으로 반환한다", async () => {
  const {memory, uploadPath} = fixture({
    "Rooms/room/MediaUploads/message": {
      ...fixture().memory.values.get("Rooms/room/MediaUploads/message"),
      processingStatus: "canceled",
    },
  });
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.published, false);
  assert.equal(result.reason, "stale_or_invalid_completion");
  assert.equal(result.readyObjects.length, 2);
  assert.equal(memory.values.has("Rooms/room/Messages/message"), false);
  assert.equal(memory.values.get("Rooms/room")?.seq, 4);
});

test("message ID 충돌은 fail closed하고 ready 객체 정리를 예약한다", async () => {
  const {memory, uploadPath} = fixture({
    "Rooms/room/Messages/message": {ID: "message", seq: 4, senderUID: "other"},
  });
  const result = await publishCompletedMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 10_000,
  });

  assert.equal(result.reason, "message_id_conflict");
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "failed");
  assert.equal(memory.values.get("Rooms/room")?.seq, 4);
});
