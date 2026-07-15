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
    assertReservation: async () => ({ ok: true, ref: { id: "reservation" } })
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
