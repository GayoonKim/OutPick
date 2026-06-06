import assert from "node:assert/strict";
import test from "node:test";

import {
  completedLifecycle,
  isFinalTaskAttempt,
} from "./job-lifecycle.js";

test("asset 결과를 top-level lifecycle로 구분한다", () => {
  assert.equal(completedLifecycle("ready"), "succeeded");
  assert.equal(completedLifecycle("partial"), "partialFailed");
  assert.equal(completedLifecycle("failed"), "failed");
});

test("세 번째 시도를 최종 Cloud Tasks 시도로 판단한다", () => {
  assert.equal(isFinalTaskAttempt(0, 3), false);
  assert.equal(isFinalTaskAttempt(1, 3), false);
  assert.equal(isFinalTaskAttempt(2, 3), true);
});
