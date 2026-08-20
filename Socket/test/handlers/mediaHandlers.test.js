import assert from "node:assert/strict";
import test from "node:test";

import { registerMediaHandlers } from "../../src/handlers/mediaHandlers.js";
import { createMessageDeliverySingleFlight } from "../../src/messages/messageDeliverySingleFlight.js";
import { createFakeSocket } from "../support/fakeSocket.js";

function register(overrides = {}) {
  const fakeSocket = createFakeSocket({ userUID: "user", userEmail: "USER@EXAMPLE.COM" });
  const timeline = [];
  const roomEmits = [];
  const mediaUploadService = {
    preflight: async () => ({
      ok: true,
      status: "pending",
      messageID: "message",
      storagePrefix: "rooms/room/messages/message",
      attachmentCount: 1,
      expectedPathCount: 2
    }),
    loadExistingMessage: async () => null,
    assertReservation: async () => ({ ok: true, ref: { id: "reservation" } }),
    preflightV2: async () => ({
      ok: true,
      contractVersion: 2,
      uploadID: "upload-v2",
      processingStatus: "uploading",
      attachmentIDs: ["attachment-v2"],
      quarantinePaths: ["room/user/upload-v2/attachment-v2/source"]
    }),
    finalizeV2: async () => ({
      ok: true,
      contractVersion: 2,
      uploadID: "upload-v2",
      processingStatus: "queued",
      messageID: null,
      seq: null,
      retryable: true
    }),
    statusV2: async () => ({
      ok: true,
      contractVersion: 2,
      uploadID: "upload-v2",
      processingStatus: "processing"
    }),
    refreshUploadTargetsV2: async () => ({
      ok: true,
      contractVersion: 2,
      uploadID: "upload-v2",
      processingStatus: "uploading",
      completedParts: [],
      uploads: []
    }),
    cancelV2: async () => ({
      ok: true,
      contractVersion: 2,
      uploadID: "upload-v2",
      processingStatus: "canceled"
    })
  };
  registerMediaHandlers({
    socket: fakeSocket.socket,
    io: {
      to: (roomID) => ({ emit: (event, payload) => {
        timeline.push("emit");
        roomEmits.push({ roomID, event, payload });
      } })
    },
    isValidRoomID: () => true,
    authorizeSocketRoom: async () => ({ ok: true }),
    allowRate: () => true,
    generateMessageID: () => "generated",
    clock: {
      nowMillis: () => 1_000,
      nowDate: () => new Date("2026-07-14T00:00:00.000Z")
    },
    mediaUploadService,
    allocateSeqAndPersist: async () => {
      timeline.push("persist");
      return { seq: 3, created: true };
    },
    messageDeliverySingleFlight: createMessageDeliverySingleFlight(),
    fanoutChatPush: async () => { timeline.push("push"); },
    imageCdnBase: "",
    logger: { log() {}, warn() {}, error() {} },
    ...overrides
  });
  return { fakeSocket, timeline, roomEmits, mediaUploadService };
}

const imagePayload = {
  kind: "images",
  roomID: "room",
  messageID: "message",
  attachments: [{
    pathThumb: "rooms/room/messages/message/thumb.jpg",
    pathOriginal: "rooms/room/messages/message/original.jpg"
  }]
};

const videoPayload = {
  kind: "video",
  roomID: "room",
  messageID: "video-message",
  storagePath: "rooms/room/messages/video-message/video.mp4",
  thumbnailPath: "rooms/room/messages/video-message/thumb.jpg"
};

test("media preflight는 service 결과 ACK를 그대로 반환한다", async () => {
  const fixture = register();
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaPreflight")({
    roomID: "room",
    messageID: "message",
    kind: "video",
    attachmentCount: 1,
    expectedPathCount: 2
  }, (value) => { ack = value; });

  assert.equal(ack.ok, true);
  assert.equal(ack.status, "pending");
  assert.equal(ack.storagePrefix, "rooms/room/messages/message");
});

test("v2 preflight/finalize는 quarantine queued 계약만 반환하고 message를 만들지 않는다", async () => {
  const fixture = register();
  const preflightCalls = [];
  const finalizeCalls = [];
  fixture.mediaUploadService.preflightV2 = async (input) => {
    preflightCalls.push(input);
    return {
      ok: true,
      contractVersion: 2,
      uploadID: input.uploadID,
      processingStatus: "uploading",
      attachmentIDs: ["a"],
      quarantinePaths: ["room/user/upload-v2/a/source"]
    };
  };
  fixture.mediaUploadService.finalizeV2 = async (input) => {
    finalizeCalls.push(input);
    return {
      ok: true,
      contractVersion: 2,
      uploadID: input.uploadID,
      processingStatus: "queued",
      messageID: null,
      seq: null,
      retryable: true
    };
  };
  let preflightACK;
  await fixture.fakeSocket.handlers.get("chat:mediaPreflight")({
    contractVersion: 2,
    roomID: "room",
    uploadID: "upload-v2",
    clientMutationID: "00000000-0000-4000-8000-000000000001",
    kind: "video",
    attachmentCount: 1,
    expectedPathCount: 1
  }, (value) => { preflightACK = value; });
  let finalizeACK;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")({
    contractVersion: 2,
    roomID: "room",
    uploadID: "upload-v2",
    clientMutationID: "00000000-0000-4000-8000-000000000001",
    kind: "video",
    attachments: [{ attachmentID: "a" }]
  }, (value) => { finalizeACK = value; });

  assert.equal(preflightACK.processingStatus, "uploading");
  assert.equal(finalizeACK.processingStatus, "queued");
  assert.equal(finalizeACK.messageID, null);
  assert.equal(finalizeACK.seq, null);
  assert.equal(preflightCalls[0].moderationPrincipalID, "principal-1");
  assert.equal(finalizeCalls[0].moderationPrincipalID, "principal-1");
  assert.equal(fixture.roomEmits.length, 0);
  assert.deepEqual(fixture.timeline, []);
});

test("v2 processing status와 cancel은 소유 principal identity를 전달한다", async () => {
  const fixture = register();
  const calls = [];
  fixture.mediaUploadService.statusV2 = async (input) => {
    calls.push(["status", input]);
    return { ok: true, processingStatus: "processing" };
  };
  fixture.mediaUploadService.cancelV2 = async (input) => {
    calls.push(["cancel", input]);
    return { ok: true, processingStatus: "canceled" };
  };
  const payload = {
    roomID: "room",
    uploadID: "upload-v2",
    clientMutationID: "00000000-0000-4000-8000-000000000001"
  };
  await fixture.fakeSocket.handlers.get("chat:mediaProcessingStatus")(payload, () => {});
  await fixture.fakeSocket.handlers.get("chat:mediaCancel")(payload, () => {});

  assert.deepEqual(calls.map(([kind]) => kind), ["status", "cancel"]);
  assert.equal(calls.every(([, input]) => input.senderUID === "user"), true);
  assert.equal(calls.every(([, input]) => input.moderationPrincipalID === "principal-1"), true);
});

test("v2 upload target refresh는 room access와 소유 principal을 검증한다", async () => {
  const fixture = register();
  let received;
  fixture.mediaUploadService.refreshUploadTargetsV2 = async (input) => {
    received = input;
    return {ok: true, processingStatus: "uploading", uploads: []};
  };
  await fixture.fakeSocket.handlers.get("chat:mediaRefreshUploadTargets")({
    roomID: "room",
    uploadID: "upload-v2",
    clientMutationID: "00000000-0000-4000-8000-000000000001"
  }, () => {});
  assert.equal(received.senderUID, "user");
  assert.equal(received.moderationPrincipalID, "principal-1");
});

test("media limiter는 principal/room/kind와 messageID를 사용한다", async () => {
  const calls = [];
  const fixture = register({
    allowRate: (...args) => { calls.push(args); return true; }
  });
  await fixture.fakeSocket.handlers.get("chat:mediaPreflight")({
    roomID: "room",
    messageID: "preflight-message",
    kind: "video",
    attachmentCount: 1,
    expectedPathCount: 2
  }, () => {});
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    imagePayload,
    () => {}
  );
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    videoPayload,
    () => {}
  );

  assert.deepEqual(calls, [
    ["principal-1:room:mediaPreflight:video", 4, 2000, "preflight-message"],
    ["principal-1:room:images", 4, 2000, "message"],
    ["principal-1:room:video", 4, 2000, "video-message"]
  ]);
});

test("image finalize winner는 persist→emit→push→ACK를 한 번 수행한다", async () => {
  const fixture = register();
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    imagePayload,
    (value) => { fixture.timeline.push("ack"); ack = value; }
  );

  assert.deepEqual(fixture.timeline, ["persist", "emit", "push", "ack"]);
  assert.deepEqual(ack, {
    ok: true,
    duplicate: false,
    messageID: "message",
    seq: 3,
    thumbTrimmed: false
  });
  assert.equal(fixture.roomEmits[0].event, "receiveImages");
  assert.equal(fixture.roomEmits[0].payload.seq, 3);
  assert.equal(Object.hasOwn(fixture.roomEmits[0].payload, "senderEmail"), false);
});

test("video persist 실패는 emit/push/success ACK를 수행하지 않는다", async () => {
  const fixture = register({
    allocateSeqAndPersist: async () => { throw new Error("failed"); }
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    videoPayload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, { ok: false, error: "seq_persist_error" });
  assert.equal(fixture.roomEmits.length, 0);
  assert.deepEqual(fixture.timeline, []);
});

test("완료된 video retry는 저장된 sender/kind/path가 같을 때만 duplicate ACK한다", async () => {
  const fixture = register();
  fixture.mediaUploadService.loadExistingMessage = async () => ({
    seq: 9,
    senderUID: "user",
    messageType: "Video",
    attachments: [{
      pathOriginal: videoPayload.storagePath,
      pathThumb: videoPayload.thumbnailPath
    }]
  });
  let reservationCount = 0;
  fixture.mediaUploadService.assertReservation = async () => {
    reservationCount += 1;
    return { ok: true, ref: {} };
  };
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    videoPayload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, {
    ok: true,
    duplicate: true,
    messageID: "video-message",
    seq: 9
  });
  assert.equal(reservationCount, 0);
  assert.equal(fixture.roomEmits.length, 0);
});

test("완료된 media retry의 sender 또는 path가 다르면 conflict로 거부한다", async () => {
  const fixture = register();
  fixture.mediaUploadService.loadExistingMessage = async () => ({
    seq: 9,
    senderUID: "other-user",
    messageType: "Image",
    attachments: [{
      pathThumb: imagePayload.attachments[0].pathThumb,
      pathOriginal: imagePayload.attachments[0].pathOriginal
    }]
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    imagePayload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, { ok: false, error: "media_message_conflict" });
  assert.equal(fixture.roomEmits.length, 0);
});

test("media reservation 검증 실패는 single-flight에 참여하지 않는다", async () => {
  let runCount = 0;
  const fixture = register({
    messageDeliverySingleFlight: {
      async run() {
        runCount += 1;
        throw new Error("must not run");
      }
    }
  });
  fixture.mediaUploadService.assertReservation = async () => ({
    ok: false,
    error: "media_reservation_sender_mismatch"
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    imagePayload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, {
    ok: false,
    error: "media_reservation_sender_mismatch"
  });
  assert.equal(runCount, 0);
});

for (const { name, payload } of [
  { name: "image", payload: imagePayload },
  { name: "video", payload: videoPayload }
]) {
  test(`동일 ${name} finalize는 persist/emit/push를 한 번만 수행한다`, async () => {
    let releasePersist;
    const persistGate = new Promise((resolve) => { releasePersist = resolve; });
    let persistCount = 0;
    const fixture = register({
      allocateSeqAndPersist: async () => {
        persistCount += 1;
        await persistGate;
        return { seq: 14, created: true };
      }
    });
    const acks = [];
    const handler = fixture.fakeSocket.handlers.get("chat:mediaFinalize");

    const owner = handler(payload, (value) => { acks.push(value); });
    const follower = handler(payload, (value) => { acks.push(value); });
    releasePersist();
    await Promise.all([owner, follower]);

    assert.equal(persistCount, 1);
    assert.equal(fixture.roomEmits.length, 1);
    assert.deepEqual(fixture.timeline, ["emit", "push"]);
    assert.deepEqual(acks.map((ack) => ack.duplicate).sort(), [false, true]);
    assert.equal(acks.every((ack) => ack.seq === 14), true);
  });
}

test("reservation 검사 중 winner가 완료되면 기존 message를 재확인해 duplicate ACK한다", async () => {
  const fixture = register();
  const existingMessage = {
    seq: 15,
    senderUID: "user",
    messageType: "Video",
    attachments: [{
      pathOriginal: videoPayload.storagePath,
      pathThumb: videoPayload.thumbnailPath
    }]
  };
  let loadCount = 0;
  fixture.mediaUploadService.loadExistingMessage = async () => {
    loadCount += 1;
    return loadCount === 1 ? null : existingMessage;
  };
  fixture.mediaUploadService.assertReservation = async () => ({
    ok: false,
    error: "media_reservation_not_found"
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")(
    videoPayload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, {
    ok: true,
    duplicate: true,
    messageID: "video-message",
    seq: 15
  });
  assert.equal(loadCount, 2);
});

test("독립 coordinator 경합에서도 transaction winner만 image를 emit/push한다", async () => {
  let persistCount = 0;
  const allocateSeqAndPersist = async () => {
    persistCount += 1;
    return { seq: 21, created: persistCount === 1 };
  };
  const first = register({ allocateSeqAndPersist });
  const second = register({ allocateSeqAndPersist });
  const acks = [];

  await Promise.all([
    first.fakeSocket.handlers.get("chat:mediaFinalize")(
      imagePayload,
      (value) => { acks.push(value); }
    ),
    second.fakeSocket.handlers.get("chat:mediaFinalize")(
      imagePayload,
      (value) => { acks.push(value); }
    )
  ]);

  assert.equal(persistCount, 2);
  assert.equal(first.roomEmits.length + second.roomEmits.length, 1);
  assert.equal(
    first.timeline.filter((item) => item === "push").length +
      second.timeline.filter((item) => item === "push").length,
    1
  );
  assert.deepEqual(acks.map((ack) => ack.duplicate).sort(), [false, true]);
});
