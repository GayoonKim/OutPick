import assert from "node:assert/strict";
import test from "node:test";

import { createRateLimiter } from "../../src/utils/rateLimit.js";

function makeClock(initial = 0) {
  let now = initial;
  return {
    clock: { nowMillis: () => now },
    advance: (milliseconds) => { now += milliseconds; }
  };
}

test("rate limiter는 key와 window별 요청 수를 제한한다", () => {
  const time = makeClock(1_000);
  const limiter = createRateLimiter({ clock: time.clock });

  assert.equal(limiter.allowRate("a", 2, 100), true);
  assert.equal(limiter.allowRate("a", 2, 100), true);
  assert.equal(limiter.allowRate("a", 2, 100), false);
  assert.equal(limiter.allowRate("b", 2, 100), true);

  time.advance(101);
  assert.equal(limiter.allowRate("a", 2, 100), true);
});

test("rate limiter instance는 bucket state를 공유하지 않는다", () => {
  const time = makeClock();
  const first = createRateLimiter({ clock: time.clock });
  const second = createRateLimiter({ clock: time.clock });

  assert.equal(first.allowRate("key", 1, 100), true);
  assert.equal(first.allowRate("key", 1, 100), false);
  assert.equal(second.allowRate("key", 1, 100), true);
});

test("같은 request ID 재시도는 window quota를 다시 소비하지 않는다", () => {
  const time = makeClock(1_000);
  const limiter = createRateLimiter({ clock: time.clock });

  assert.equal(limiter.allowRate("key", 1, 100, "message-1"), true);
  assert.equal(limiter.allowRate("key", 1, 100, "message-1"), true);
  assert.equal(limiter.allowRate("key", 1, 100, "message-2"), false);

  time.advance(101);
  assert.equal(limiter.allowRate("key", 1, 100, "message-1"), true);
});

test("idle TTL sweep는 오래된 bucket을 제거한다", () => {
  const time = makeClock(1_000);
  const limiter = createRateLimiter({
    clock: time.clock,
    idleTTLms: 60,
    sweepIntervalMs: 30
  });

  assert.equal(limiter.allowRate("a", 1, 10), true);
  assert.equal(limiter.activeBucketCount(), 1);
  time.advance(60);
  assert.equal(limiter.sweep(), 1);
  assert.equal(limiter.activeBucketCount(), 0);
});

test("bucket cap 도달 시 새 key를 fail closed하고 기존 key는 유지한다", () => {
  const time = makeClock(1_000);
  const capacityEvents = [];
  const limiter = createRateLimiter({
    clock: time.clock,
    maxActiveBuckets: 1,
    onCapacity: (event) => capacityEvents.push(event)
  });

  assert.equal(limiter.allowRate("a", 2, 100), true);
  assert.equal(limiter.allowRate("b", 2, 100), false);
  assert.equal(limiter.allowRate("a", 2, 100), true);
  assert.deepEqual(capacityEvents, [{ activeBuckets: 1, maxActiveBuckets: 1 }]);
});
