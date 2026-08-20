import assert from "node:assert/strict";
import test from "node:test";
import {messageStorageTargets} from "./service.js";

test("v2 attachment는 bucket과 message prefix를 cleanup target으로 보존한다", () => {
  const targets = messageStorageTargets("room", "message", {
    attachments: [{
      bucketOriginal: "outpick-test-chat-media",
      pathOriginal: "rooms/room/messages/message/attachments/a/display",
      bucketThumb: "outpick-test-chat-media",
      pathThumb: "rooms/room/messages/message/attachments/a/thumbnail",
    }],
  });
  assert.deepEqual(targets, [{
    bucket: "outpick-test-chat-media",
    prefix: "rooms/room/messages/message",
  }]);
});

test("bucket이 없는 v1 attachment는 기본 bucket target으로 호환한다", () => {
  const targets = messageStorageTargets("room", "message", {
    attachments: [{
      pathOriginal: "rooms/room/messages/message/original.jpg",
      pathThumb: "rooms/room/messages/message/thumb.jpg",
    }],
  });
  assert.deepEqual(targets, [{
    bucket: null,
    prefix: "rooms/room/messages/message",
  }]);
});

test("다른 message prefix는 cleanup target으로 수용하지 않는다", () => {
  assert.deepEqual(messageStorageTargets("room", "message", {
    attachments: [{
      bucketOriginal: "outpick-test-chat-media",
      pathOriginal: "rooms/room/messages/other/attachments/a/display",
    }],
  }), []);
});
