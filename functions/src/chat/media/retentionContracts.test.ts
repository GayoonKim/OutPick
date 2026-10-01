/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  chatMediaExpiryJobID,
  chatMediaExpiryNextAttemptAt,
  nextChatMediaExpiryAttemptAt,
} from "./retentionContracts.js";

test("만료 원장 ID는 Socket과 같은 room/message NUL 구분 계약을 따른다", () => {
  const expected = createHash("sha256")
    .update("room-1\0message-1")
    .digest("hex");
  assert.equal(chatMediaExpiryJobID("room-1", "message-1"), expected);
});

test("실패는 다음 서울 정시 회차로 예약하고 evidence 해제는 아직 이르지 않은 미디어 만료를 따른다", () => {
  const now = new Date("2026-09-30T10:24:00.000Z");
  assert.equal(
    nextChatMediaExpiryAttemptAt(now).toDate().toISOString(),
    "2026-09-30T11:00:00.000Z",
  );
  const expiry = Timestamp.fromDate(new Date("2026-09-30T11:30:00.000Z"));
  assert.equal(
    chatMediaExpiryNextAttemptAt(expiry, now).toMillis(),
    expiry.toMillis(),
  );
  const afterExpiry = new Date("2026-09-30T12:00:00.000Z");
  assert.equal(
    chatMediaExpiryNextAttemptAt(expiry, afterExpiry).toDate().toISOString(),
    "2026-09-30T12:00:00.000Z",
  );
});
