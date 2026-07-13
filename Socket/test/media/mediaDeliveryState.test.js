import assert from "node:assert/strict";
import test from "node:test";

import { createMediaDeliveryState } from "../../src/media/mediaDeliveryState.js";

test("image와 video delivered key를 독립적으로 관리한다", () => {
  const state = createMediaDeliveryState();
  state.add("images", "room:message");

  assert.equal(state.has("images", "room:message"), true);
  assert.equal(state.has("video", "room:message"), false);

  state.remove("images", "room:message");
  assert.equal(state.has("images", "room:message"), false);
});

test("기존처럼 최대 개수 초과 시 해당 kind Set 전체를 비운다", () => {
  const state = createMediaDeliveryState({ maxKeys: 2 });
  state.add("images", "one");
  state.add("images", "two");
  state.add("images", "three");

  assert.equal(state.size("images"), 0);
});
