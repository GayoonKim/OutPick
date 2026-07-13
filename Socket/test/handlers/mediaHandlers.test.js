import assert from "node:assert/strict";
import test from "node:test";

import { registerMediaHandlers } from "../../src/handlers/mediaHandlers.js";
import { createMediaDeliveryState } from "../../src/media/mediaDeliveryState.js";
import { createFakeSocket } from "../support/fakeSocket.js";

function register(overrides = {}) {
  const fakeSocket = createFakeSocket({ userUID: "user", userEmail: "USER@EXAMPLE.COM" });
  const timeline = [];
  const roomEmits = [];
  const mediaDeliveryState = createMediaDeliveryState();
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
    mediaDeliveryState,
    mediaUploadService,
    allocateSeqAndPersist: async () => { timeline.push("persist"); return 3; },
    fanoutChatPush: async () => { timeline.push("push"); },
    imageCdnBase: "",
    logger: { log() {}, warn() {}, error() {} },
    ...overrides
  });
  return { fakeSocket, timeline, roomEmits, mediaDeliveryState, mediaUploadService };
}

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

test("image finalize 성공은 persist→emit→push→ACK와 delivered key를 유지한다", async () => {
  const fixture = register();
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")({
    kind: "images",
    roomID: "room",
    messageID: "message",
    attachments: [{
      pathThumb: "rooms/room/messages/message/thumb.jpg",
      pathOriginal: "rooms/room/messages/message/original.jpg"
    }]
  }, (value) => { fixture.timeline.push("ack"); ack = value; });

  assert.deepEqual(fixture.timeline, ["persist", "emit", "push", "ack"]);
  assert.deepEqual(ack, { ok: true, messageID: "message", thumbTrimmed: false });
  assert.equal(fixture.roomEmits[0].event, "receiveImages");
  assert.equal(fixture.mediaDeliveryState.has("images", "room:message"), true);
});

test("video persist 실패는 delivered key를 해제하고 emit/push를 하지 않는다", async () => {
  const fixture = register({
    allocateSeqAndPersist: async () => { throw new Error("failed"); }
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")({
    kind: "video",
    roomID: "room",
    messageID: "video-message",
    storagePath: "rooms/room/messages/video-message/video.mp4",
    thumbnailPath: "rooms/room/messages/video-message/thumb.jpg"
  }, (value) => { ack = value; });

  assert.deepEqual(ack, { ok: false, error: "seq_persist_error" });
  assert.equal(fixture.mediaDeliveryState.has("video", "room:video-message"), false);
  assert.equal(fixture.roomEmits.length, 0);
  assert.deepEqual(fixture.timeline, []);
});

test("기존 message가 있으면 duplicate ACK와 seq를 반환한다", async () => {
  const fixture = register();
  fixture.mediaDeliveryState.add("video", "room:message");
  fixture.mediaUploadService.loadExistingMessage = async () => ({ seq: 9 });
  let ack;
  await fixture.fakeSocket.handlers.get("chat:mediaFinalize")({
    kind: "video",
    roomID: "room",
    messageID: "message"
  }, (value) => { ack = value; });

  assert.deepEqual(ack, {
    ok: true,
    duplicate: true,
    messageID: "message",
    seq: 9
  });
});
