/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {
  claimMediaUploadForExecution,
  reconcileStaleMediaUpload,
} from "./orchestrationService.js";

function memoryFirestore(initial: Record<string, Record<string, unknown>>) {
  const values = new Map(Object.entries(initial));
  const reference = (path: string): Record<string, unknown> => ({
    path,
    id: path.split("/").at(-1),
  });
  const collection = (path: string) => ({
    doc: (id: string) => reference(`${path}/${id}`),
  });
  const firestore = {
    collection,
    runTransaction: async (operation: (transaction: Record<string, unknown>) => unknown) => {
      const transaction = {
        get: async (ref: {path: string}) => {
          const data = values.get(ref.path);
          return {exists: data !== undefined, data: () => data, ref};
        },
        set: (ref: {path: string}, data: Record<string, unknown>, options?: {merge?: boolean}) => {
          values.set(ref.path, options?.merge ?
            {...(values.get(ref.path) ?? {}), ...data} : {...data});
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

test("queued upload은 고정 slot 하나만 claim하고 중복 dispatcher는 거부한다", async () => {
  const uploadPath = "Rooms/room/MediaUploads/upload";
  const memory = memoryFirestore({
    [uploadPath]: {
      contractVersion: 2,
      kind: "images",
      processingStatus: "queued",
      processingAttempt: 0,
      processingDeadlineAt: Timestamp.fromMillis(100_000),
      nextAttemptAt: Timestamp.fromMillis(1_000),
    },
  });
  const uploadRef = memory.reference(uploadPath) as never;
  const first = await claimMediaUploadForExecution({
    firestore: memory.firestore,
    uploadRef,
    projectID: "outpick-test",
    nowMillis: 2_000,
    leaseToken: "lease-a",
  });
  const duplicate = await claimMediaUploadForExecution({
    firestore: memory.firestore,
    uploadRef,
    projectID: "outpick-test",
    nowMillis: 3_000,
    leaseToken: "lease-b",
  });

  assert.deepEqual(first, {
    claimed: true,
    leaseToken: "lease-a",
    slotID: "image-0",
    kind: "images",
  });
  assert.deepEqual(duplicate, {
    claimed: false,
    reason: "already_claimed",
    duplicate: true,
  });
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "processing");
  assert.equal(memory.values.get(uploadPath)?.processingAttempt, 1);
  assert.equal(
    memory.values.get("chatMediaProcessingSlots/image-0")?.leaseOwnerUploadPath,
    uploadPath
  );
});

test("만료 processing lease는 재시도 횟수가 남으면 queued로 되돌리고 principal slot을 유지한다", async () => {
  const uploadPath = "Rooms/room/MediaUploads/upload";
  const memory = memoryFirestore({
    [uploadPath]: {
      contractVersion: 2,
      kind: "video",
      processingStatus: "processing",
      processingAttempt: 1,
      processingDeadlineAt: Timestamp.fromMillis(100_000),
      leaseToken: "lease-a",
      leaseExpiresAt: Timestamp.fromMillis(1_000),
      processingSlotID: "video-0",
      principalSlotID: "principal_video_0",
      quarantinePaths: ["room/user/upload/attachment/source"],
    },
    "chatMediaProcessingSlots/video-0": {
      leaseToken: "lease-a",
      leaseOwnerUploadPath: uploadPath,
      leaseExpiresAt: Timestamp.fromMillis(1_000),
    },
    "chatMediaPrincipalUploadSlots/principal_video_0": {
      ownerUploadPath: uploadPath,
    },
  });
  const result = await reconcileStaleMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 2_000,
  });

  assert.equal(result.reason, "retry_queued");
  assert.equal(result.terminal, false);
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "queued");
  assert.equal(memory.values.get("chatMediaProcessingSlots/video-0")?.leaseToken, null);
  assert.equal(
    memory.values.get("chatMediaPrincipalUploadSlots/principal_video_0")?.ownerUploadPath,
    uploadPath
  );
});

test("최대 시도 processing lease 만료는 failed와 7일 TTL로 끝내고 두 slot을 반환한다", async () => {
  const uploadPath = "Rooms/room/MediaUploads/upload";
  const memory = memoryFirestore({
    [uploadPath]: {
      contractVersion: 2,
      kind: "video",
      processingStatus: "processing",
      processingAttempt: 3,
      processingDeadlineAt: Timestamp.fromMillis(100_000),
      leaseToken: "lease-a",
      leaseExpiresAt: Timestamp.fromMillis(1_000),
      processingSlotID: "video-0",
      principalSlotID: "principal_video_0",
      quarantinePaths: ["room/user/upload/attachment/source"],
    },
    "chatMediaProcessingSlots/video-0": {
      leaseToken: "lease-a",
      leaseOwnerUploadPath: uploadPath,
    },
    "chatMediaPrincipalUploadSlots/principal_video_0": {
      ownerUploadPath: uploadPath,
    },
  });
  const result = await reconcileStaleMediaUpload({
    firestore: memory.firestore,
    uploadRef: memory.reference(uploadPath) as never,
    nowMillis: 2_000,
  });

  assert.equal(result.terminal, true);
  assert.deepEqual(result.quarantinePaths, [
    "room/user/upload/attachment/source",
  ]);
  assert.equal(memory.values.get(uploadPath)?.processingStatus, "failed");
  assert.equal(memory.values.get("chatMediaProcessingSlots/video-0")?.leaseToken, null);
  assert.equal(
    memory.values.get("chatMediaPrincipalUploadSlots/principal_video_0")?.ownerUploadPath,
    null
  );
  const expiresAt = memory.values.get(uploadPath)?.expiresAt as Timestamp;
  assert.equal(expiresAt.toMillis(), 2_000 + 7 * 24 * 60 * 60 * 1000);
});
