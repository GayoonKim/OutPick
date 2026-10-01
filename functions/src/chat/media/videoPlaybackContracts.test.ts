import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  parseIssueChatMediaURLInput,
  parseIssueChatVideoPlaybackURLInput,
} from "./videoPlaybackContracts.js";

test("공통 미디어 요청은 ID와 variant만 허용한다", () => {
  const ids = {
    roomID: "room", messageID: "message", attachmentID: "attachment",
  };
  for (const variant of ["original", "thumbnail"]) {
    assert.deepEqual(
      parseIssueChatMediaURLInput({...ids, variant}), {...ids, variant},
    );
  }
  for (const data of [
    {...ids}, {...ids, variant: "other"},
    {...ids, variant: "original", path: "forged"},
  ]) {
    assert.throws(() => parseIssueChatMediaURLInput(data), HttpsError);
  }
});

test("영상 playback URL 입력은 세 문서 ID만 받는다", () => {
  assert.deepEqual(parseIssueChatVideoPlaybackURLInput({
    roomID: " room ",
    messageID: "message-1",
    attachmentID: "attachment-1",
  }), {
    roomID: "room",
    messageID: "message-1",
    attachmentID: "attachment-1",
  });
});

test("임의 Storage 경로·기한·추가 필드와 잘못된 ID를 거부한다", () => {
  assert.throws(() => parseIssueChatVideoPlaybackURLInput({
    roomID: "room",
    messageID: "message-1",
    attachmentID: "attachment-1",
    path: "arbitrary/path",
  }), HttpsError);
  assert.throws(() => parseIssueChatVideoPlaybackURLInput({
    roomID: "room",
    messageID: "message-1",
    attachmentID: "attachment-1",
    expiresAt: "2099-01-01T00:00:00.000Z",
  }), HttpsError);
  assert.throws(() => parseIssueChatVideoPlaybackURLInput({
    roomID: "room/other",
    messageID: "message-1",
    attachmentID: "attachment-1",
  }), HttpsError);
  assert.throws(() => parseIssueChatVideoPlaybackURLInput(null), HttpsError);
});
