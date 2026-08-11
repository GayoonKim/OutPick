/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  parseAcknowledgeRoomClosureInput,
  parseCloseOwnedChatRoomInput,
  parseCloseRoomByModerationInput,
  parseDeleteChatMessageInput,
} from "./contracts.js";

const requestID = "123e4567-e89b-42d3-a456-426614174000";

test("message deletion 계약은 expected seq와 선택적 신고 참조를 정규화한다", () => {
  assert.deepEqual(parseDeleteChatMessageInput({
    roomID: "room-1",
    messageID: "message-1",
    expectedSeq: 7,
    reasonCode: "chatMessageDeletion",
    reportTargetType: "room",
    reportTargetID: "room-1",
    clientRequestID: requestID.toUpperCase(),
  }), {
    roomID: "room-1",
    messageID: "message-1",
    expectedSeq: 7,
    reasonCode: "chatMessageDeletion",
    reportTargetType: "room",
    reportTargetID: "room-1",
    clientRequestID: requestID,
  });
});

test("message deletion 계약은 seq 0과 불완전한 신고 참조를 거부한다", () => {
  assert.throws(() => parseDeleteChatMessageInput({
    roomID: "room-1",
    messageID: "message-1",
    expectedSeq: 0,
    clientRequestID: requestID,
  }), HttpsError);
  assert.throws(() => parseDeleteChatMessageInput({
    roomID: "room-1",
    messageID: "message-1",
    expectedSeq: 1,
    reportTargetType: "room",
    clientRequestID: requestID,
  }), HttpsError);
});

test("owner와 moderation room close 계약은 lifecycle version과 관리자 사유를 구분한다", () => {
  assert.deepEqual(parseCloseOwnedChatRoomInput({
    roomID: "room-1",
    expectedLifecycleVersion: 2,
    clientRequestID: requestID,
  }), {
    roomID: "room-1",
    expectedLifecycleVersion: 2,
    clientRequestID: requestID,
  });
  assert.deepEqual(parseCloseRoomByModerationInput({
    roomID: "room-1",
    expectedLifecycleVersion: 2,
    reasonCode: "policyViolation",
    reportTargetID: "room-1",
    clientRequestID: requestID,
  }), {
    roomID: "room-1",
    expectedLifecycleVersion: 2,
    reasonCode: "policyViolation",
    reportTargetID: "room-1",
    clientRequestID: requestID,
  });
  assert.throws(() => parseCloseRoomByModerationInput({
    roomID: "room-1",
    expectedLifecycleVersion: 2,
    clientRequestID: requestID,
  }), HttpsError);
});

test("room closure 확인 계약은 room과 request ID를 정규화한다", () => {
  assert.deepEqual(parseAcknowledgeRoomClosureInput({
    roomID: "room-1",
    clientRequestID: requestID.toUpperCase(),
  }), {
    roomID: "room-1",
    clientRequestID: requestID,
  });
});
