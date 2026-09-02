import assert from "node:assert/strict";
import test from "node:test";
import {
  retryableSuccessionError,
  successionRetryDelayMillis,
  nextRoomSuccessionAttempt,
  roomSuccessionExpired,
} from "./roomSuccessionPolicy.js";

test("방별 승계는 최대 4회이며 마지막 시도도 50초 기한 전에 예약한다", () => {
  assert.deepEqual(
    Array.from({length: 4}, (_, index) => successionRetryDelayMillis(index)),
    [0, 5_000, 15_000, 20_000],
  );
  assert.equal(successionRetryDelayMillis(4), null);
});

test("50초 경계와 처리 지연이 있으면 다음 시도를 예약하지 않는다", () => {
  assert.equal(roomSuccessionExpired(50_000, 49_999), false);
  assert.equal(roomSuccessionExpired(50_000, 50_000), true);
  assert.equal(roomSuccessionExpired(NaN, 0), true);
  assert.equal(nextRoomSuccessionAttempt(3, 50_000, 20_000), 40_000);
  assert.equal(nextRoomSuccessionAttempt(3, 50_000, 30_000), null);
  assert.equal(nextRoomSuccessionAttempt(4, 50_000, 40_000), null);
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
