import assert from "node:assert/strict";
import test from "node:test";

import { registerConnectionHandlers } from "../../src/handlers/connectionHandlers.js";
import { createFakeIO, createFakeSocket } from "../support/fakeSocket.js";

test("connection handler는 ready/room list와 hello/ping/username 계약을 유지한다", () => {
  const fakeSocket = createFakeSocket({
    handshake: {
      auth: { clientKey: "client-key" }, headers: {}, query: {}, address: "address"
    }
  });
  const fakeIO = createFakeIO();
  const rooms = { roomA: [] };
  const policy = { maxAttempts: 5 };

  registerConnectionHandlers({
    socket: fakeSocket.socket,
    io: fakeIO.io,
    rooms,
    clock: { nowMillis: () => 1234 },
    reconnectPolicy: policy,
    logger: { log() {} }
  });

  assert.deepEqual(fakeSocket.emitted.slice(0, 2), [
    {
      event: "server:connect:ready",
      payload: { policy, serverTime: 1234, socketId: "socket-1" }
    },
    { event: "room list", payload: ["roomA"] }
  ]);

  let helloACK;
  fakeSocket.handlers.get("client:hello")({ attempt: 2 }, (value) => { helloACK = value; });
  assert.deepEqual(helloACK, {
    ok: true,
    attempt: 2,
    policy,
    serverTime: 1234,
    key: "client-key"
  });

  let pingACK;
  fakeSocket.handlers.get("client:ping")((value) => { pingACK = value; });
  assert.deepEqual(pingACK, { pong: true, serverTime: 1234 });

  fakeSocket.handlers.get("set username")();
  assert.equal(fakeSocket.socket.username, "Anonymous");
  assert.deepEqual(fakeSocket.emitted.at(-1), {
    event: "username set",
    payload: "Anonymous"
  });
});

test("disconnect는 모든 room의 username을 제거하고 user list를 emit한다", () => {
  const fakeSocket = createFakeSocket({ username: "Alice" });
  const fakeIO = createFakeIO();
  const rooms = { one: ["Alice", "Bob"], two: ["Alice"] };

  registerConnectionHandlers({
    socket: fakeSocket.socket,
    io: fakeIO.io,
    rooms,
    clock: { nowMillis: () => 0 },
    reconnectPolicy: {},
    logger: { log() {} }
  });
  fakeSocket.handlers.get("disconnect")();

  assert.deepEqual(rooms, { one: ["Bob"], two: [] });
  assert.equal(fakeIO.roomEmits.length, 2);
});
