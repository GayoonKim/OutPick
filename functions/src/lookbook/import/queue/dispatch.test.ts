import assert from "node:assert/strict";
import test from "node:test";
import {isQueueDispatchStale} from "./dispatch.js";

test("PQ13 배달 회수는 queued·delivered 경계에서만 15분 뒤 같은 전달을 다시 연다", () => {
  const base = {state: "queued" as const, dispatchState: "delivered" as const,
    dispatchDeliveredAt: 1_000};
  assert.equal(isQueueDispatchStale(base, 1_000 + 899_999), false);
  assert.equal(isQueueDispatchStale(base, 1_000 + 900_000), true);
  assert.equal(isQueueDispatchStale(
    {...base, state: "active"}, 1_000 + 900_000), false);
  assert.equal(isQueueDispatchStale({...base, dispatchState: "pending"},
    1_000 + 900_000), false);
  assert.equal(isQueueDispatchStale({...base, dispatchDeliveredAt: "1000"},
    1_000 + 900_000), false);
});
