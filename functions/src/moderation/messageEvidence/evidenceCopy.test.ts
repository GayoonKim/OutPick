/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  MessageEvidenceCopyError,
  validateMessageEvidenceSources,
} from "./evidenceCopy.js";

const imageSource = {
  attachmentID: "attachment-1",
  bucket: "ready-bucket",
  path: "rooms/room/messages/message/attachments/attachment-1/display",
  generation: "123",
  bytes: 1024,
  contentType: "image/jpeg",
};

test("ready source descriptor는 환경·메시지·attachment 경로를 exact 검증한다", () => {
  assert.deepEqual(validateMessageEvidenceSources({
    roomID: "room",
    messageID: "message",
    messageType: "image",
    readyBucket: "ready-bucket",
    sources: [imageSource],
  }), [imageSource]);
  for (const source of [
    {...imageSource, bucket: "production-bucket"},
    {...imageSource, path: "rooms/other/messages/message/attachments/attachment-1/display"},
    {...imageSource, path: "rooms/room/messages/message/attachments/attachment-1/thumbnail"},
    {...imageSource, generation: "not-a-generation"},
  ]) {
    assert.throws(
      () => validateMessageEvidenceSources({roomID: "room", messageID: "message", messageType: "image", readyBucket: "ready-bucket", sources: [source]}),
      (error) => error instanceof MessageEvidenceCopyError && error.code === "INVALID_EVIDENCE_SOURCE",
    );
  }
});

test("image와 video는 개수와 MIME 계약을 서로 바꿔 사용할 수 없다", () => {
  assert.throws(() => validateMessageEvidenceSources({
    roomID: "room", messageID: "message", messageType: "video", readyBucket: "ready-bucket", sources: [imageSource],
  }));
  const video = {...imageSource, contentType: "video/mp4"};
  assert.deepEqual(validateMessageEvidenceSources({
    roomID: "room", messageID: "message", messageType: "video", readyBucket: "ready-bucket", sources: [video],
  }), [video]);
  assert.throws(() => validateMessageEvidenceSources({
    roomID: "room", messageID: "message", messageType: "video", readyBucket: "ready-bucket", sources: [video, {...video, attachmentID: "attachment-2", path: "rooms/room/messages/message/attachments/attachment-2/display"}],
  }));
});

test("attachment ID 중복은 destination 충돌 전에 거부한다", () => {
  assert.throws(() => validateMessageEvidenceSources({
    roomID: "room",
    messageID: "message",
    messageType: "image",
    readyBucket: "ready-bucket",
    sources: [imageSource, imageSource],
  }));
});

test("ready source는 image/video 실제 출력 크기 상한을 넘으면 거부한다", () => {
  assert.throws(() => validateMessageEvidenceSources({
    roomID: "room",
    messageID: "message",
    messageType: "image",
    readyBucket: "ready-bucket",
    sources: [{...imageSource, bytes: 15 * 1024 * 1024 + 1}],
  }), /bytes exceed/);
  assert.throws(() => validateMessageEvidenceSources({
    roomID: "room",
    messageID: "message",
    messageType: "video",
    readyBucket: "ready-bucket",
    sources: [{...imageSource, contentType: "video/mp4", bytes: 350 * 1024 * 1024 + 1}],
  }), /bytes exceed/);
});
