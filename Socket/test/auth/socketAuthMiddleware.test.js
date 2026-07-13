import assert from "node:assert/strict";
import test from "node:test";

import {
  createFirebaseAuthMiddleware,
  createReconnectAttemptMiddleware
} from "../../src/auth/socketAuthMiddleware.js";

const reconnectPolicy = {
  maxAttempts: 5,
  baseDelayMs: 500,
  maxDelayMs: 8000,
  windowMs: 60_000
};

function silentLogger() {
  return { log() {}, warn() {}, error() {} };
}

test("reconnect middleware는 같은 client key의 여섯 번째 요청을 거부한다", () => {
  let now = 1_000;
  const middleware = createReconnectAttemptMiddleware({
    clock: { nowMillis: () => now },
    reconnectPolicy,
    logger: silentLogger()
  });
  const socket = {
    handshake: {
      auth: { clientKey: "client" },
      headers: {}, query: {}, address: "address"
    }
  };

  for (let index = 0; index < 5; index += 1) {
    let received;
    middleware(socket, (error) => { received = error; });
    assert.equal(received, undefined);
  }

  let received;
  middleware(socket, (error) => { received = error; });
  assert.equal(received.message, "max_connect_attempts_exceeded");
  assert.deepEqual(received.data, {
    message: "연결 시도 횟수를 초과했습니다. 잠시 후 다시 시도하세요.",
    maxAttempts: 5,
    retryAfterMs: 8000
  });

  now += 60_001;
  middleware(socket, (error) => { received = error; });
  assert.equal(received, undefined);
});

test("Firebase auth middleware는 profile email을 우선해 socket identity를 설정한다", async () => {
  const socket = {
    handshake: { auth: { idToken: " token " }, headers: {} }
  };
  const middleware = createFirebaseAuthMiddleware({
    verifyIDToken: async (token) => {
      assert.equal(token, "token");
      return { uid: " user-1 ", email: "token@example.com" };
    },
    findUserByUID: async () => ({
      ref: { id: "document-1" },
      data: { email: "profile@example.com" }
    }),
    logger: silentLogger()
  });

  let received;
  await middleware(socket, (error) => { received = error; });
  assert.equal(received, undefined);
  assert.equal(socket.userUID, "user-1");
  assert.equal(socket.userDocumentID, "document-1");
  assert.equal(socket.userEmail, "profile@example.com");
  assert.equal(socket.userEmailSource, "profile");
});

test("Firebase auth middleware는 missing/invalid token error 계약을 유지한다", async () => {
  const missing = createFirebaseAuthMiddleware({
    verifyIDToken: async () => ({}),
    findUserByUID: async () => null,
    logger: silentLogger()
  });
  let missingError;
  await missing({ handshake: { auth: {}, headers: {} } }, (error) => {
    missingError = error;
  });
  assert.equal(missingError.message, "unauthenticated");
  assert.equal(missingError.data.error, "missing_id_token");

  const invalid = createFirebaseAuthMiddleware({
    verifyIDToken: async () => { throw new Error("invalid"); },
    findUserByUID: async () => null,
    logger: silentLogger()
  });
  let invalidError;
  await invalid(
    { handshake: { auth: { token: "bad" }, headers: {} } },
    (error) => { invalidError = error; }
  );
  assert.equal(invalidError.message, "unauthenticated");
  assert.equal(invalidError.data.error, "invalid_id_token");
});
