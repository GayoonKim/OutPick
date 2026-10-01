/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {issueChatVideoPlaybackURLService, type ChatVideoPlaybackURLSigner} from "./videoPlaybackService.js";

const roomID = "room-1";
const messageID = "message-1";
const attachmentID = "attachment-1";
const readyBucket = "chat-ready";
const objectPath = `rooms/${roomID}/messages/${messageID}/attachments/${attachmentID}/display`;
const generation = "1740000000000000";
const nowMillis = Date.parse("2026-09-30T00:00:00.000Z");

function fakeFirestore(overrides: {
  room?: Record<string, unknown> | null;
  message?: Record<string, unknown> | null;
} = {}): Firestore {
  const documents = new Map<string, Record<string, unknown> | null>([
    [`Rooms/${roomID}`, overrides.room === undefined ? {
      isClosed: false,
      lifecycleStatus: "active",
    } : overrides.room],
    [`Rooms/${roomID}/Messages/${messageID}`, overrides.message === undefined ? {
      mediaContractVersion: 3,
      mediaExpiresAt: Timestamp.fromMillis(nowMillis + 30 * 60 * 1000),
      readyAttachmentIDs: [attachmentID],
      isDeleted: false,
      moderationVisibilityState: "visible",
      attachments: [{
        attachmentID,
        type: "video",
        bucketOriginal: readyBucket,
        pathOriginal: objectPath,
        generationOriginal: generation,
        contentTypeOriginal: "video/mp4",
      }],
    } : overrides.message],
  ]);
  const reference = (path: string) => ({
    collection: (name: string) => collection(`${path}/${name}`),
    get: async () => {
      const data = documents.get(path);
      return {
        exists: data !== undefined && data !== null,
        data: () => data ?? undefined,
        get: (key: string) => data?.[key],
      };
    },
  });
  const collection = (path: string) => ({
    doc: (id: string) => reference(`${path}/${id}`),
  });
  const firestore = {
    collection,
  };
  return firestore as unknown as Firestore;
}

function signer(overrides: {
  metadata?: () => Promise<Record<string, unknown>>;
  sign?: (expiresAt: Date) => Promise<string>;
} = {}) {
  const calls: {metadata: number; signedExpiry: Date | null} = {
    metadata: 0,
    signedExpiry: null,
  };
  const value: ChatVideoPlaybackURLSigner = {
    metadata: async () => {
      calls.metadata += 1;
      return overrides.metadata ? overrides.metadata() : {
        generation,
        contentType: "video/mp4",
      };
    },
    sign: async (_object, expiresAt) => {
      calls.signedExpiry = expiresAt;
      return overrides.sign ? overrides.sign(expiresAt) : "https://signed.invalid/video";
    },
  };
  return {value, calls};
}

function request() {
  return {roomID, messageID, attachmentID};
}

test("공통 원본과 썸네일도 권한·숨김·삭제·만료 및 잘못된 generation을 거절한다", async (t) => {
  for (const variant of ["original", "thumbnail"] as const) {
    for (const failure of ["account", "closed", "hidden", "deleted", "expired", "generation"]) {
      await t.test(`${variant}/${failure}`, async () => {
        let metadataCalls = 0;
        let signCalls = 0;
        const message = {
          mediaContractVersion: 3,
          mediaExpiresAt: Timestamp.fromMillis(nowMillis + (failure === "expired" ? 0 : 600_000)),
          readyAttachmentIDs: [attachmentID],
          isDeleted: failure === "deleted",
          moderationVisibilityState: failure === "hidden" ? "hiddenPendingReview" : "visible",
          attachments: [{attachmentID, type: "image", bucketOriginal: readyBucket,
            pathOriginal: objectPath, generationOriginal: generation, contentTypeOriginal: "image/png",
            bucketThumb: readyBucket, pathThumb: objectPath.replace(/display$/, "thumbnail"),
            generationThumb: generation}],
        };
        await assert.rejects(issueChatVideoPlaybackURLService({
          actorUID: "viewer", request: request(), variant, readyBucket,
          firestore: fakeFirestore({message, room: {isClosed: failure === "closed"}}),
          now: () => new Date(nowMillis),
          authorize: async () => {
            if (failure === "account") throw new HttpsError("permission-denied", "synthetic");
          },
          signer: {
            metadata: async () => {
              metadataCalls += 1;
              return {generation: "999", contentType: variant === "thumbnail" ? "image/jpeg" : "image/png"};
            },
            sign: async () => {
              signCalls += 1;
              return "https://signed.invalid/media";
            },
          },
        }), (error: unknown) => error instanceof HttpsError);
        assert.equal(signCalls, 0);
        assert.equal(metadataCalls, failure === "generation" ? 1 : 0);
      });
    }
  }
});

test("공통 발급은 사진 GIF와 썸네일의 exact generation을 서명한다", async () => {
  for (const [type, contentType, variant] of [
    ["image", "image/png", "original"], ["image", "image/gif", "original"],
    ["image", "image/jpeg", "thumbnail"], ["video", "video/mp4", "original"],
    ["video", "image/jpeg", "thumbnail"],
  ] as const) {
    const thumbnail = variant === "thumbnail";
    const path = objectPath.replace(/display$/, thumbnail ? "thumbnail" : "display");
    const result = await issueChatVideoPlaybackURLService({
      actorUID: "viewer", request: request(), variant, readyBucket,
      firestore: fakeFirestore({message: {
        mediaContractVersion: 3, mediaExpiresAt: Timestamp.fromMillis(nowMillis + 7200_000),
        readyAttachmentIDs: [attachmentID], isDeleted: false,
        attachments: [{attachmentID, type, bucketOriginal: readyBucket, pathOriginal: objectPath,
          generationOriginal: generation, contentTypeOriginal: type === "image" ? contentType : "video/mp4",
          bucketThumb: readyBucket, pathThumb: path, generationThumb: "456"}],
      }}),
      signer: {
        metadata: async (object) => {
          assert.equal(object.path, path); assert.equal(object.generation, thumbnail ? "456" : generation);
          return {generation: object.generation, contentType};
        },
        sign: async (_object, expiry) => {
          assert.equal(expiry.getTime(), nowMillis + 3600_000);
          return "https://signed.invalid/media";
        },
      },
      now: () => new Date(nowMillis), authorize: async () => undefined,
    });
    assert.equal(result.generation, thumbnail ? "456" : generation);
  }
});

function errorCode(error: unknown): unknown {
  const details = error instanceof HttpsError ?
    error.details as Record<string, unknown> : undefined;
  return details?.errorCode;
}

test("유효한 영상은 서버가 저장한 exact object와 만료 상한으로 서명한다", async () => {
  const storage = signer();
  const result = await issueChatVideoPlaybackURLService({
    actorUID: "viewer",
    request: request(),
    readyBucket,
    firestore: fakeFirestore(),
    signer: storage.value,
    now: () => new Date(nowMillis),
    authorize: async (uid) => assert.equal(uid, "viewer"),
  });

  assert.equal(result.url, "https://signed.invalid/video");
  assert.equal(result.urlExpiresAt, new Date(nowMillis + 30 * 60 * 1000).toISOString());
  assert.equal(result.mediaExpiresAt, new Date(nowMillis + 30 * 60 * 1000).toISOString());
  assert.equal(storage.calls.metadata, 1);
  assert.equal(storage.calls.signedExpiry?.getTime(), nowMillis + 30 * 60 * 1000);
});

test("미디어 기한이 충분하면 URL은 발급 시각에서 한 시간을 넘지 않는다", async () => {
  const storage = signer({metadata: async () => ({
    generation,
    contentType: "video/quicktime",
  })});
  const message = {
    mediaContractVersion: 3,
    mediaExpiresAt: Timestamp.fromMillis(nowMillis + 3 * 60 * 60 * 1000),
    readyAttachmentIDs: [attachmentID],
    attachments: [{
      attachmentID,
      type: "video",
      bucketOriginal: readyBucket,
      pathOriginal: objectPath,
      generationOriginal: generation,
      contentTypeOriginal: "video/quicktime",
    }],
  };
  const result = await issueChatVideoPlaybackURLService({
    actorUID: "viewer",
    request: request(),
    readyBucket,
    firestore: fakeFirestore({message}),
    signer: storage.value,
    now: () => new Date(nowMillis),
    authorize: async () => Promise.resolve(),
  });

  assert.equal(result.urlExpiresAt, new Date(nowMillis + 60 * 60 * 1000).toISOString());
});

test("실패 조건은 URL을 발급하지 않고 fail closed한다", async (t) => {
  const cases: Array<{
    name: string;
    firestore?: Firestore;
    now?: () => Date;
    readyBucket?: string;
    expectedCode?: string;
  }> = [
    {
      name: "비활성 방",
      firestore: fakeFirestore({room: {isClosed: true}}),
      expectedCode: "CHAT_ROOM_CLOSED",
    },
    {
      name: "삭제 메시지",
      firestore: fakeFirestore({message: {
        mediaContractVersion: 3,
        mediaExpiresAt: Timestamp.fromMillis(nowMillis + 10_000),
        readyAttachmentIDs: [attachmentID],
        isDeleted: true,
      }}),
    },
    {
      name: "숨김 메시지",
      firestore: fakeFirestore({message: {
        mediaContractVersion: 3,
        mediaExpiresAt: Timestamp.fromMillis(nowMillis + 10_000),
        readyAttachmentIDs: [attachmentID],
        moderationVisibilityState: "hiddenPendingReview",
      }}),
    },
    {
      name: "만료 미디어",
      firestore: fakeFirestore({message: {
        mediaContractVersion: 3,
        mediaExpiresAt: Timestamp.fromMillis(nowMillis),
        readyAttachmentIDs: [attachmentID],
      }}),
      expectedCode: "MEDIA_EXPIRED",
    },
    {
      name: "구형 계약 메시지",
      firestore: fakeFirestore({message: {
        mediaContractVersion: 2,
        mediaExpiresAt: Timestamp.fromMillis(nowMillis + 10_000),
        readyAttachmentIDs: [attachmentID],
      }}),
    },
    {
      name: "잘못된 대상 버킷",
      readyBucket: "another-bucket",
    },
  ];

  for (const entry of cases) {
    await t.test(entry.name, async () => {
      const storage = signer();
      await assert.rejects(issueChatVideoPlaybackURLService({
        actorUID: "viewer",
        request: request(),
        readyBucket: entry.readyBucket ?? readyBucket,
        firestore: entry.firestore ?? fakeFirestore(),
        signer: storage.value,
        now: entry.now ?? (() => new Date(nowMillis)),
        authorize: async () => Promise.resolve(),
      }), (error: unknown) => {
        if (entry.expectedCode) assert.equal(errorCode(error), entry.expectedCode);
        return error instanceof HttpsError;
      });
      assert.equal(storage.calls.signedExpiry, null);
    });
  }
});

test("첨부 소속·영상 유형·generation·Storage metadata가 다르면 서명하지 않는다", async (t) => {
  const invalidAttachments = [
    {attachmentID, type: "image", bucketOriginal: readyBucket, pathOriginal: objectPath,
      generationOriginal: generation, contentTypeOriginal: "image/jpeg"},
    {attachmentID, type: "video", bucketOriginal: readyBucket, pathOriginal: "other/path",
      generationOriginal: generation, contentTypeOriginal: "video/mp4"},
    {attachmentID, type: "video", bucketOriginal: readyBucket, pathOriginal: objectPath,
      generationOriginal: "0", contentTypeOriginal: "video/mp4"},
  ];
  for (const attachment of invalidAttachments) {
    await t.test(JSON.stringify(attachment), async () => {
      const storage = signer();
      const message = {
        mediaContractVersion: 3,
        mediaExpiresAt: Timestamp.fromMillis(nowMillis + 60_000),
        readyAttachmentIDs: [attachmentID],
        attachments: [attachment],
      };
      await assert.rejects(issueChatVideoPlaybackURLService({
        actorUID: "viewer",
        request: request(),
        readyBucket,
        firestore: fakeFirestore({message}),
        signer: storage.value,
        now: () => new Date(nowMillis),
        authorize: async () => Promise.resolve(),
      }), HttpsError);
      assert.equal(storage.calls.signedExpiry, null);
    });
  }

  for (const metadata of [
    {generation: "1740000000000001", contentType: "video/mp4"},
    {generation, contentType: "image/jpeg"},
  ]) {
    await t.test(`metadata ${JSON.stringify(metadata)}`, async () => {
      const storage = signer({metadata: async () => metadata});
      await assert.rejects(issueChatVideoPlaybackURLService({
        actorUID: "viewer",
        request: request(),
        readyBucket,
        firestore: fakeFirestore(),
        signer: storage.value,
        now: () => new Date(nowMillis),
        authorize: async () => Promise.resolve(),
      }), HttpsError);
      assert.equal(storage.calls.signedExpiry, null);
    });
  }
});

test("서명 도중 만료되면 서명 결과를 반환하지 않는다", async () => {
  let currentMillis = nowMillis;
  const storage = signer({
    sign: async () => {
      currentMillis = nowMillis + 31 * 60 * 1000;
      return "https://signed.invalid/expired-before-return";
    },
  });
  await assert.rejects(issueChatVideoPlaybackURLService({
    actorUID: "viewer",
    request: request(),
    readyBucket,
    firestore: fakeFirestore(),
    signer: storage.value,
    now: () => new Date(currentMillis),
    authorize: async () => Promise.resolve(),
  }), (error: unknown) => errorCode(error) === "MEDIA_EXPIRED");
});
