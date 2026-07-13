import assert from "node:assert/strict";
import test from "node:test";

import {
  buildServerVideoMessage,
  enforceThumbBudget,
  normalizeImageAttachment,
  sanitizeImageItem,
  withDerivedImageURLs
} from "../../src/media/mediaPayload.js";

test("legacy image alias와 CDN URL을 attachment schema로 정규화한다", () => {
  const item = withDerivedImageURLs(
    sanitizeImageItem({ storagePath: "path/image.jpg", width: 10, height: 20 }),
    "https://cdn.example.com"
  );
  const attachment = normalizeImageAttachment({
    originalUrl: item.originalUrl,
    width: item.width,
    height: item.height
  }, 0);

  assert.equal(item.originalUrl, "https://cdn.example.com/path%2Fimage.jpg");
  assert.equal(attachment.pathOriginal, item.originalUrl);
  assert.equal(attachment.w, 10);
  assert.equal(attachment.h, 20);
});

test("thumbnail budget 초과 시 뒤 attachment부터 thumbData를 제거한다", () => {
  const first = { thumbData: Buffer.alloc(4) };
  const second = { thumbData: Buffer.alloc(4) };
  const result = enforceThumbBudget([first, second], 5);

  assert.equal(result.thumbTrimmed, true);
  assert.equal(Buffer.isBuffer(first.thumbData), true);
  assert.equal(second.thumbData, undefined);
});

test("video attachment metadata와 server message field를 유지한다", () => {
  const value = buildServerVideoMessage({
    roomID: "room",
    messageID: "message",
    senderUID: "user",
    msg: "video",
    attachments: [{
      storagePath: "video.mp4",
      thumbnailPath: "thumb.jpg",
      duration: 2.5,
      approxBitrateMbps: 3,
      preset: "medium"
    }]
  }, new Date("2026-07-14T00:00:00.000Z"));

  assert.equal(value.messageType, "Video");
  assert.equal(value.attachments[0].pathOriginal, "video.mp4");
  assert.equal(value.attachments[0].pathThumb, "thumb.jpg");
  assert.equal(value.attachments[0].duration, 2.5);
});
