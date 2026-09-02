import assert from "node:assert/strict";
import test from "node:test";
import {
  retryableSuccessionError,
  successionRetryDelayMillis,
} from "./roomMembershipSweep.js";

test("승계 작업은 최초 포함 4회, 총 50초 안에 실패를 확정한다", () => {
  assert.deepEqual(
    Array.from({length: 4}, (_, index) => successionRetryDelayMillis(index)),
    [0, 5_000, 15_000, 30_000],
  );
  assert.equal(successionRetryDelayMillis(4), null);
});

test("일시적 Firestore 오류와 후보 경쟁만 재시도한다", () => {
  assert.equal(retryableSuccessionError({code: 14}), true);
  assert.equal(retryableSuccessionError({code: "aborted"}), true);
  assert.equal(
    retryableSuccessionError(new Error("room_successor_changed")),
    true,
  );
  assert.equal(retryableSuccessionError({code: "permission-denied"}), false);
  assert.equal(
    retryableSuccessionError(new Error("room_owner_projection_invalid")),
    false,
  );
});
