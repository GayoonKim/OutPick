import assert from "node:assert/strict";
import test from "node:test";

import {
  canFinalizePurgeLease,
  isManualRetryDuplicate,
  isPurgeLeaseActive,
  shouldStartManualRetryTrigger,
  visibleManualRetryState,
} from "./lookbookDeletionPurgeLease.js";

test("lease는 만료 시각 전까지만 유효하다", () => {
  assert.equal(isPurgeLeaseActive(2_000, 1_999), true);
  assert.equal(isPurgeLeaseActive(2_000, 2_000), false);
  assert.equal(isPurgeLeaseActive(null, 1_000), false);
});

test("manual retry trigger는 새 queued token에만 반응한다", () => {
  assert.equal(
    shouldStartManualRetryTrigger(null, "token-1", "queued"),
    true
  );
  assert.equal(
    shouldStartManualRetryTrigger("token-1", "token-1", "queued"),
    false
  );
  assert.equal(
    shouldStartManualRetryTrigger("token-1", "token-2", "running"),
    false
  );
  assert.equal(
    shouldStartManualRetryTrigger(null, null, "queued"),
    false
  );
});

test("현재 lease owner만 purge 결과를 finalize한다", () => {
  assert.equal(canFinalizePurgeLease("lease-1", "lease-1"), true);
  assert.equal(canFinalizePurgeLease("lease-2", "lease-1"), false);
  assert.equal(canFinalizePurgeLease(null, "lease-1"), false);
});

test("queued 상태 또는 유효 request lease는 중복 retry다", () => {
  assert.equal(isManualRetryDuplicate("queued", false), true);
  assert.equal(isManualRetryDuplicate("running", true), true);
  assert.equal(isManualRetryDuplicate("running", false), false);
  assert.equal(isManualRetryDuplicate("failed", true), true);
  assert.equal(isManualRetryDuplicate("failed", false), false);
  assert.equal(isManualRetryDuplicate(null, false), false);
});

test("만료 lease의 stale running은 화면에서 failed로 보인다", () => {
  assert.equal(visibleManualRetryState("running", true), "running");
  assert.equal(visibleManualRetryState("running", false), "failed");
  assert.equal(visibleManualRetryState("queued", false), "queued");
});
