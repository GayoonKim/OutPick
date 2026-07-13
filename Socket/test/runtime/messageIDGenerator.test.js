import assert from "node:assert/strict";
import test from "node:test";

import { createMessageIDGenerator } from "../../src/runtime/messageIDGenerator.js";

test("현재 timestamp-random hex message ID 형식을 유지한다", () => {
  const generate = createMessageIDGenerator({
    clock: { nowMillis: () => 1234 },
    random: () => 0.5
  });

  assert.equal(generate(), "1234-8");
});
