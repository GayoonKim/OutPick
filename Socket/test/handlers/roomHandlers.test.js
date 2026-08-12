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

test("읽기 권한만 있고 joinRoom 권한이 없으면 participant socket 입장을 거부한다", async () => {
  const fixture = register();
  fixture.fakeSocket.socket.allowedCapabilities = ["readAppContent"];
  let ack;
  await fixture.fakeSocket.handlers.get("join room")("room", (value) => { ack = value; });
  assert.equal(ack.ok, false);
  assert.equal(fixture.fakeSocket.joined.length, 0);
});

test("owner close는 watcher에 종료 side effect를 맡기고 ACK만 반환한다", async () => {
  const fixture = register({
    leaveOrCloseRoom: async () => ({ ok: true, mode: "closed", alreadyDeleted: false })
  });

  let ack;
  await fixture.fakeSocket.handlers.get("room:leave-or-close")(
    { roomID: "room" },
    (value) => { ack = value; }
  );

  assert.deepEqual(ack, { ok: true, mode: "closed", alreadyDeleted: false });
  assert.equal(fixture.fakeIO.roomEmits.length, 0);
  assert.notEqual(fixture.rooms.room, undefined);
  assert.deepEqual(fixture.fakeIO.memberSocket.left, []);
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
