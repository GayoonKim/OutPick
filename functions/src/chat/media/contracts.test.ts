import assert from "node:assert/strict";
import test from "node:test";
import {
  deterministicMediaTaskID,
  processingSlotIDs,
} from "./contracts.js";

test("환경과 kind별 고정 execution slot 수를 유지한다", () => {
  assert.deepEqual(processingSlotIDs("outpick-test", "images"), ["image-0"]);
  assert.deepEqual(processingSlotIDs("outpick-test", "video"), ["video-0"]);
  assert.deepEqual(processingSlotIDs("outpick-664ae", "images"), [
    "image-0", "image-1", "image-2", "image-3",
  ]);
  assert.deepEqual(processingSlotIDs("outpick-664ae", "video"), ["video-0"]);
});

test("media task ID는 upload path와 dispatch generation에 결정적이다", () => {
  const first = deterministicMediaTaskID("Rooms/r/MediaUploads/u", 1);
  assert.equal(first, deterministicMediaTaskID("Rooms/r/MediaUploads/u", 1));
  assert.notEqual(first, deterministicMediaTaskID("Rooms/r/MediaUploads/u", 2));
  assert.match(first, /^chat-media-[a-f0-9]{40}$/);
});
