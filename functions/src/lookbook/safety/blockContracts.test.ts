/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {parseBlockUserInput, parseUnblockUserInput} from "./blockContracts.js";

const requestID = "123e4567-e89b-42d3-a456-426614174000";

test("전역 차단 요청은 chat source와 canonical 필드를 허용한다", () => {
  assert.deepEqual(parseBlockUserInput({
    targetUID: "target-user",
    source: "chat",
    targetNicknameSnapshot: " 대상 ",
    clientRequestID: requestID.toUpperCase(),
  }), {
    targetUID: "target-user",
    source: "chat",
    targetNicknameSnapshot: "대상",
    clientRequestID: requestID,
  });
});

test("전역 차단 요청은 자기 문서 경계를 벗어나는 UID와 미지원 source를 거부한다", () => {
  for (const input of [
    {targetUID: "a/b", source: "chat", clientRequestID: requestID},
    {targetUID: "target", source: "room", clientRequestID: requestID},
  ]) {
    assert.throws(() => parseBlockUserInput(input), HttpsError);
  }
});

test("차단 해제 요청은 UUID clientRequestID를 요구한다", () => {
  assert.deepEqual(parseUnblockUserInput({
    targetUID: "target-user",
    clientRequestID: requestID,
  }), {
    targetUID: "target-user",
    clientRequestID: requestID,
  });
  assert.throws(
    () => parseUnblockUserInput({
      targetUID: "target-user",
      clientRequestID: "retry",
    }),
    HttpsError,
  );
  assert.throws(() => parseUnblockUserInput({
    targetUID: "target-user",
    clientRequestID: requestID,
    blockerUserID: "forged-user",
  }), HttpsError);
});
