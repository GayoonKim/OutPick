import assert from "node:assert/strict";
import test from "node:test";

import {
  buildTextMessageDocument,
  normalizeReplyPreview
} from "../../src/messages/messagePayload.js";

test("reply preview alias와 optional field를 기존 schema로 정규화한다", () => {
  assert.deepEqual(normalizeReplyPreview({
    messageID: "reply",
    sender: "Bob",
    text: "text",
    images: 2,
    videosCount: 1,
    senderAvatarPath: "avatars/bob",
    sentAt: 1_700_000_000
  }), {
    messageID: "reply",
    sender: "Bob",
    text: "text",
    imagesCount: 2,
    videosCount: 1,
    senderAvatarPath: "avatars/bob",
    sentAt: "2023-11-14T22:13:20.000Z",
    isDeleted: false
  });
});

test("text server document 기본 field를 유지한다", () => {
  const value = buildTextMessageDocument({
    data: { senderAvatarPath: "avatar" },
    roomID: "room",
    messageID: "message",
    msg: "hello",
    senderUID: "user",
    senderEmail: "user@example.com",
    nickname: "Alice",
    nowDate: new Date("2026-07-14T00:00:00.000Z")
  });

  assert.deepEqual(value, {
    ID: "message",
    roomID: "room",
    roomName: "room",
    senderUID: "user",
    senderEmail: "user@example.com",
    senderNickname: "Alice",
    senderAvatarPath: "avatar",
    msg: "hello",
    message: "hello",
    messageType: "Text",
    isFailed: false,
    isDeleted: false,
    sentAt: "2026-07-14T00:00:00.000Z",
    attachments: []
  });
});
