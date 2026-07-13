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
