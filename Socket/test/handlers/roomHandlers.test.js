import assert from "node:assert/strict";
import test from "node:test";

import { registerRoomHandlers } from "../../src/handlers/roomHandlers.js";
import { createFakeSocket } from "../support/fakeSocket.js";

function createRoomIO() {
  const roomEmits = [];
  const memberSocket = { left: [], leave(roomID) { this.left.push(roomID); } };
  return {
    roomEmits,
    memberSocket,
    io: {
      to(roomID) {
        return { emit: (event, payload) => roomEmits.push({ roomID, event, payload }) };
      },
      sockets: {
        adapter: { rooms: new Map([["room", new Set(["member-socket`"])]]) },
        sockets: new Map([["member-socket`", memberSocket]])
      }
    }
  };
}

function register(overrides = {}) {
  const fakeSocket = createFakeSocket({
    userUID: "user",
    username: "Alice"
  });
  const fakeIO = createRoomIO();
  const rooms = { room: ["Alice", "Bob"] };
  registerRoomHandlers({
    socket: fakeSocket.socket,
    io: fakeIO.io,
    rooms,
    isValidRoomID: (roomID) => roomID === "room" || roomID === "new-room",
    ensureRoomLoaded: async () => true,
    loadRoomAccess: async () => ({ ok: true }),
    leaveOrCloseRoom: async () => ({ ok: true, mode: "left" }),
    logger: { log() {}, warn() {}, error() {} },
    ...overrides
  });
  return { fakeSocket, fakeIO, rooms };
}

test("create/join/leave room ACK와 registry side effect를 유지한다", async () => {
  const fixture = register();

  let invalid;
  fixture.fakeSocket.handlers.get("create room")("invalid", (value) => { invalid = value; });
  assert.deepEqual(invalid, { ok: false, message: "invalid_room_id" });

  let created;
  fixture.fakeSocket.handlers.get("create room")("new-room", (value) => { created = value; });
  assert.deepEqual(created, { ok: true, roomID: "new-room" });
  assert.deepEqual(fixture.rooms["new-room"], ["Alice"]);

  let joined;
  await fixture.fakeSocket.handlers.get("join room")("room", (value) => { joined = value; });
  assert.deepEqual(joined, { ok: true, roomID: "room" });
  assert.equal(fixture.fakeSocket.emitted.at(-1).event, "joined room");

  let left;
  fixture.fakeSocket.handlers.get("leave room")("room", (value) => { left = value; });
  assert.deepEqual(left, { ok: true, roomID: "room" });
  assert.deepEqual(fixture.rooms.room, ["Bob"]);
});

test("owner close는 room:closed, registry 삭제, room socket leave 후 ACK한다", async () => {
  const fixture = register({
    leaveOrCloseRoom: async () => ({ ok: true, mode: "closed", alreadyDeleted: false })
  });

  let ack;
  await fixture.fakeSocket.handlers.get("room:leave-or-close")(
    { roomID: "room" },
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, { ok: true, mode: "closed", alreadyDeleted: false });
  assert.equal(fixture.fakeIO.roomEmits[0].event, "room:closed");
  assert.equal(fixture.rooms.room, undefined);
  assert.deepEqual(fixture.fakeIO.memberSocket.left, ["room"]);
});

test("이미 삭제된 room은 기존처럼 socket close side effect 없이 성공한다", async () => {
  const fixture = register({
    leaveOrCloseRoom: async () => ({
      ok: true,
      mode: "closed",
      alreadyDeleted: true,
      skipSocketCloseEffects: true
    })
  });

  let ack;
  await fixture.fakeSocket.handlers.get("room:leave-or-close")(
    { roomID: "room" },
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, { ok: true, mode: "closed", alreadyDeleted: true });
  assert.equal(fixture.fakeIO.roomEmits.length, 0);
  assert.notEqual(fixture.rooms.room, undefined);
});
