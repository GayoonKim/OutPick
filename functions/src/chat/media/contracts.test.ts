import assert from "node:assert/strict";
import test from "node:test";
import {
  deterministicMediaTaskID,
  processingSlotIDs,
} from "./contracts.js";

test("출시 전 환경과 kind별 execution 기본 상한은 1이다", () => {
  assert.deepEqual(processingSlotIDs("outpick-test", "images"), ["image-0"]);
  assert.deepEqual(processingSlotIDs("outpick-test", "video"), ["video-0"]);
  assert.deepEqual(processingSlotIDs("outpick-664ae", "images"), [
    "image-0",
  ]);
  assert.deepEqual(processingSlotIDs("outpick-664ae", "video"), ["video-0"]);
});

test("execution 상한은 kind별 운영 설정으로 조절한다", () => {
  const key = "CHAT_MEDIA_IMAGE_EXECUTION_LIMIT";
  const previous = process.env[key];
  try {
    process.env[key] = "3";
    assert.deepEqual(processingSlotIDs("outpick-test", "images"),
      ["image-0", "image-1", "image-2"]);
    process.env[key] = "0";
    assert.throws(() => processingSlotIDs("outpick-test", "images"));
    process.env[key] = "1.5";
    assert.throws(() => processingSlotIDs("outpick-test", "images"));
  } finally {
    if (previous === undefined) delete process.env[key];
    else process.env[key] = previous;
  }
});

test("media task ID는 upload path와 dispatch generation에 결정적이다", () => {
  const first = deterministicMediaTaskID("Rooms/r/MediaUploads/u", 1);
  assert.equal(first, deterministicMediaTaskID("Rooms/r/MediaUploads/u", 1));
  assert.notEqual(first, deterministicMediaTaskID("Rooms/r/MediaUploads/u", 2));
  assert.match(first, /^chat-media-[a-f0-9]{40}$/);
});
