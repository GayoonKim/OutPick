import assert from "node:assert/strict";
import test from "node:test";

import { registerMessageHandlers } from "../../src/handlers/messageHandlers.js";
import { createFakeSocket } from "../support/fakeSocket.js";

function register(overrides = {}) {
  const fakeSocket = createFakeSocket({
    userUID: "user-1",
    userEmail: "USER@EXAMPLE.COM"
  });
  const timeline = [];
  const roomEmits = [];
  registerMessageHandlers({
    socket: fakeSocket.socket,
    io: {
      to: (roomID) => ({
        emit: (event, payload) => {
          timeline.push("emit");
          roomEmits.push({ roomID, event, payload });
        }
      })
    },
    isValidRoomID: () => true,
    authorizeSocketRoom: async () => ({ ok: true }),
    allowRate: () => true,
    generateMessageID: () => "generated-id",
    clock: { nowDate: () => new Date("2026-07-14T00:00:00.000Z") },
    allocateSeqAndPersist: async () => { timeline.push("persist"); return 7; },
    fanoutChatPush: async () => { timeline.push("push"); },
    handleLookbookShare: async () => {},
    logger: { log() {}, warn() {}, error() {} },
    ...overrides
  });
  return { fakeSocket, timeline, roomEmits };
}

test("text message 성공은 persist→emit→push→ACK 순서와 ACK key를 유지한다", async () => {
  const fixture = register();
  let ack;
  await fixture.fakeSocket.handlers.get("chat message")({
    roomID: "room",
    msg: "hello",
    senderNickname: "Alice"
  }, (value) => {
    fixture.timeline.push("ack");
    ack = value;
  });

  assert.deepEqual(fixture.timeline, ["persist", "emit", "push", "ack"]);
  assert.deepEqual(ack, {
    ok: true,
    success: true,
    seq: 7,
    messageID: "generated-id"
  });
  assert.equal(fixture.roomEmits[0].event, "chat message");
  assert.equal(fixture.roomEmits[0].payload.senderEmail, "user@example.com");
  assert.equal(fixture.roomEmits[0].payload.sentAt, "2026-07-14T00:00:00.000Z");
});

test("text persist 실패는 emit/push/success ACK를 수행하지 않는다", async () => {
  const fixture = register({
    allocateSeqAndPersist: async () => { throw new Error("failed"); }
  });
  let ack;
  await fixture.fakeSocket.handlers.get("chat message")(
    { roomID: "room", msg: "hello" },
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, {
    ok: false,
    message: "seq_persist_error",
    error: "seq_persist_error"
  });
  assert.equal(fixture.roomEmits.length, 0);
  assert.deepEqual(fixture.timeline, []);
});

test("text validation/access/rate error 계약을 유지한다", async () => {
  const invalid = register({ isValidRoomID: () => false });
  let invalidACK;
  await invalid.fakeSocket.handlers.get("chat message")(
    { roomID: "bad", msg: "hello" },
    (value) => { invalidACK = value; }
  );
  assert.deepEqual(invalidACK, {
    ok: false,
    message: "invalid_room_id",
    error: "invalid_room_id"
  });

  const denied = register({
    authorizeSocketRoom: async () => ({ ok: false, error: "not_joined" })
  });
  let deniedACK;
  await denied.fakeSocket.handlers.get("chat message")(
    { roomID: "room", msg: "hello" },
    (value) => { deniedACK = value; }
  );
  assert.equal(deniedACK.error, "not_joined");

  const limited = register({ allowRate: () => false });
  let limitedACK;
  await limited.fakeSocket.handlers.get("chat message")(
    { roomID: "room", msg: "hello" },
    (value) => { limitedACK = value; }
  );
  assert.equal(limitedACK.error, "rate_limited");
});

test("lookbook event는 기존 handler에 한 번 위임한다", async () => {
  const calls = [];
  const fixture = register({
    handleLookbookShare: async (...args) => { calls.push(args); }
  });
  const callback = () => {};
  await fixture.fakeSocket.handlers.get("chat:lookbookShare")({ value: 1 }, callback);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], fixture.fakeSocket.socket);
  assert.deepEqual(calls[0][1], { value: 1 });
  assert.equal(calls[0][2], callback);
});
