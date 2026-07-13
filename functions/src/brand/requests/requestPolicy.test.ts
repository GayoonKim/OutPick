/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  brandRequestUserListScope,
  dateKeyKST,
  requestStatusForAdminStage,
} from "./functions.js";

test("브랜드 요청 일자 키는 Asia/Seoul 날짜를 사용한다", () => {
  assert.equal(dateKeyKST(new Date("2026-01-01T14:59:59.000Z")), "20260101");
  assert.equal(dateKeyKST(new Date("2026-01-01T15:00:00.000Z")), "20260102");
});

test("admin stage를 사용자 status로 매핑한다", () => {
  assert.equal(requestStatusForAdminStage("requested"), "submitted");
  assert.equal(requestStatusForAdminStage("processing"), "reviewing");
  assert.equal(requestStatusForAdminStage("completed"), "added");
  assert.equal(requestStatusForAdminStage("rejected"), "rejected");
});

test("사용자 목록 scope 기본값과 유효성 계약을 유지한다", () => {
  assert.equal(brandRequestUserListScope({}), "active");
  assert.equal(brandRequestUserListScope({scope: "history"}), "history");
  assert.throws(
    () => brandRequestUserListScope({scope: "unknown"}),
    HttpsError
  );
});
