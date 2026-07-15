import assert from "node:assert/strict";
import test from "node:test";

import { createLookbookShareHandler } from "../../src/lookbookShare/lookbookShareHandler.js";
import { createMessageDeliverySingleFlight } from "../../src/messages/messageDeliverySingleFlight.js";
import { createFakeSocket } from "../support/fakeSocket.js";

function createFixture(overrides = {}) {
  const fakeSocket = createFakeSocket({
    userUID: "user",
    userEmail: "USER@EXAMPLE.COM",
    rooms: new Set(["room"])
  });
  const timeline = [];
  const roomEmits = [];
  const handler = createLookbookShareHandler({
    io: {
      to: (roomID) => ({ emit: (event, payload) => {
        timeline.push("emit");
        roomEmits.push({ roomID, event, payload });
      } })
    },
    rooms: { room: { id: "room" } },
    isValidRoomID: () => true,
    ensureRoomLoaded: async () => true,
    loadRoomAccess: async () => ({ ok: true }),
    allocateSeqAndPersist: async () => {
      timeline.push("persist");
      return { seq: 5, created: true };
    },
    messageDeliverySingleFlight: createMessageDeliverySingleFlight(),
    fanoutChatPush: async () => { timeline.push("push"); },
    allowRate: () => true,
    clock: { nowDate: () => new Date("2026-07-15T00:00:00.000Z") },
    generateMessageID: () => "generated-id",
    logger: { log() {}, warn() {}, error() {} },
    ...overrides
  });
  return { fakeSocket, handler, timeline, roomEmits };
}

const payload = {
  roomID: "room",
  ID: "lookbook-message",
  msg: "공유합니다",
  senderNickname: "Alice",
  sharedContent: {
    schemaVersion: 1,
    contentType: "brand",
    brandID: "brand",
    titleSnapshot: "Brand"
  }
};

test("Lookbook winner는 persist→emit→push 뒤 duplicate false ACK한다", async () => {
  const fixture = createFixture();
  let ack;
  await fixture.handler(fixture.fakeSocket.socket, payload, (value) => {
    fixture.timeline.push("ack");
    ack = value;
  });

  assert.deepEqual(fixture.timeline, ["persist", "emit", "push", "ack"]);
  assert.deepEqual(ack, {
    ok: true,
    success: true,
    duplicate: false,
    seq: 5,
    messageID: "lookbook-message"
  });
  assert.equal(fixture.roomEmits[0].event, "chat message");
  assert.equal(fixture.roomEmits[0].payload.messageType, "lookbookShare");
});

test("동일 Lookbook 요청은 persist/emit/push를 한 번만 수행한다", async () => {
  let releasePersist;
  const persistGate = new Promise((resolve) => { releasePersist = resolve; });
  let persistCount = 0;
  const fixture = createFixture({
    allocateSeqAndPersist: async () => {
      persistCount += 1;
      await persistGate;
      return { seq: 6, created: true };
    }
  });
  const acks = [];

  const owner = fixture.handler(
    fixture.fakeSocket.socket,
    payload,
    (value) => { acks.push(value); }
  );
  const follower = fixture.handler(
    fixture.fakeSocket.socket,
    payload,
    (value) => { acks.push(value); }
  );
  releasePersist();
  await Promise.all([owner, follower]);

  assert.equal(persistCount, 1);
  assert.equal(fixture.roomEmits.length, 1);
  assert.deepEqual(fixture.timeline, ["emit", "push"]);
  assert.deepEqual(acks.map((ack) => ack.duplicate).sort(), [false, true]);
  assert.equal(acks.every((ack) => ack.seq === 6), true);
});

test("Lookbook transaction loser는 기존 seq만 ACK하고 emit/push하지 않는다", async () => {
  const fixture = createFixture({
    allocateSeqAndPersist: async () => ({ seq: 8, created: false })
  });
  let ack;
  await fixture.handler(
    fixture.fakeSocket.socket,
    payload,
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, {
    ok: true,
    success: true,
    duplicate: true,
    seq: 8,
    messageID: "lookbook-message"
  });
  assert.equal(fixture.roomEmits.length, 0);
  assert.deepEqual(fixture.timeline, []);
});
