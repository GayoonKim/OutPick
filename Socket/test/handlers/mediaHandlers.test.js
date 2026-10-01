import assert from "node:assert/strict";
import test from "node:test";

import {registerMediaHandlers} from "../../src/handlers/mediaHandlers.js";
import {createMessageDeliverySingleFlight} from "../../src/messages/messageDeliverySingleFlight.js";
import {createFakeSocket} from "../support/fakeSocket.js";

function register() {
  const fakeSocket = createFakeSocket({userUID: "user", userEmail: "USER@EXAMPLE.COM"});
  const calls = [];
  const mediaUploadService = Object.fromEntries([
    ["preflightDirect", "preflight"], ["finalizeDirect", "finalize"],
    ["refreshDirect", "refresh"], ["statusDirect", "status"], ["cancelDirect", "cancel"]
  ].map(([method, kind]) => [method, async input => {
    calls.push([kind, input]);
    return {ok: true, contractVersion: 3, processingStatus: kind === "finalize" ? "ready" : "uploading",
      uploadID: input.uploadID, messageID: input.uploadID, seq: 7,
      sentAt: "2026-09-30T00:00:00.000Z", mediaExpiresAt: "2026-10-07T00:00:00.000Z",
      uploads: []};
  }]));
  registerMediaHandlers({
    socket: fakeSocket.socket, io: {to: () => ({emit() {}})},
    isValidRoomID: () => true, authorizeSocketRoom: async () => ({ok: true}),
    allowRate: () => true, generateMessageID: () => "generated",
    clock: {nowMillis: () => 1000, nowDate: () => new Date("2026-09-30T00:00:00.000Z")},
    mediaUploadService, allocateSeqAndPersist: async () => assert.fail("직접 확정은 handler가 다시 저장하지 않는다"),
    messageDeliverySingleFlight: createMessageDeliverySingleFlight(),
    fanoutChatPush: async () => assert.fail("직접 업로드 전송은 delivery worker가 처리한다"),
    imageCdnBase: "", logger: {log() {}, warn() {}, error() {}}
  });
  return {fakeSocket, calls};
}

const request = {
  contractVersion: 3, roomID: "room", uploadID: "message",
  clientMutationID: "00000000-0000-4000-8000-000000000001", kind: "images",
  attachmentCount: 1, expectedPathCount: 2, sources: []
};

test("계약3 preflight만 직접 업로드 예약 API로 연결한다", async () => {
  const f = register();
  let ack;
  await f.fakeSocket.handlers.get("chat:mediaPreflight")(request, value => { ack = value; });
  assert.equal(ack.ok, true);
  assert.equal(f.calls[0][0], "preflight");
  assert.equal(f.calls[0][1].senderUID, "user");
  assert.equal(f.calls[0][1].moderationPrincipalID, "principal-1");
});

test("구형·누락 계약의 예약과 finalize는 거절한다", async () => {
  const f = register();
  for (const contractVersion of [undefined, 1, 2]) {
    let preflight, finalize;
    await f.fakeSocket.handlers.get("chat:mediaPreflight")({...request, contractVersion}, value => { preflight = value; });
    await f.fakeSocket.handlers.get("chat:mediaFinalize")({...request, contractVersion}, value => { finalize = value; });
    assert.equal(preflight.error, "unsupported_media_contract");
    assert.equal(finalize.error, "unsupported_media_contract");
  }
  assert.deepEqual(f.calls, []);
});

test("finalize ACK는 서버 확정 시각을 그대로 전달하고 클라이언트 시각을 전달하지 않는다", async () => {
  const f = register();
  let ack;
  await f.fakeSocket.handlers.get("chat:mediaFinalize")({
    ...request, sentAt: "1999-01-01T00:00:00.000Z", mediaExpiresAt: "2099-01-01T00:00:00.000Z"
  }, value => { ack = value; });
  assert.equal(ack.sentAt, "2026-09-30T00:00:00.000Z");
  assert.equal(ack.mediaExpiresAt, "2026-10-07T00:00:00.000Z");
  assert.deepEqual(f.calls[0], ["finalize", {
    roomID: "room", uploadID: "message", clientMutationID: request.clientMutationID,
    senderUID: "user", moderationPrincipalID: "principal-1"
  }]);
});

test("refresh/status/cancel은 계약3 직접 업로드 API만 사용한다", async () => {
  const f = register();
  const body = {...request, attachmentCount: undefined, expectedPathCount: undefined, sources: undefined};
  for (const event of ["chat:mediaRefreshUploadTargets", "chat:mediaProcessingStatus", "chat:mediaCancel"]) {
    let ack;
    await f.fakeSocket.handlers.get(event)(body, value => { ack = value; });
    assert.equal(ack.ok, true);
  }
  assert.deepEqual(f.calls.map(([kind]) => kind), ["refresh", "status", "cancel"]);
});

test("refresh/status/cancel은 계약3 외에는 거절한다", async () => {
  const f = register();
  const body = {...request, attachmentCount: undefined, expectedPathCount: undefined, sources: undefined, contractVersion: 2};
  for (const event of ["chat:mediaRefreshUploadTargets", "chat:mediaProcessingStatus", "chat:mediaCancel"]) {
    let ack;
    await f.fakeSocket.handlers.get(event)(body, value => { ack = value; });
    assert.equal(ack.error, "unsupported_media_contract");
  }
  assert.deepEqual(f.calls, []);
});
