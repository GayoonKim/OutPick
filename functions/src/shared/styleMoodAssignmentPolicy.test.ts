/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  MAX_ASSIGNED_STYLE_MOOD_COUNT,
  requiredStyleMoodIDs,
} from "./styleMoodAssignmentPolicy.js";

test("브랜드와 시즌 무드는 0개부터 5개의 고유 ID를 허용한다", () => {
  assert.deepEqual(requiredStyleMoodIDs([]), []);
  assert.deepEqual(requiredStyleMoodIDs(["minimal", "street"]), [
    "minimal",
    "street",
  ]);
  assert.deepEqual(requiredStyleMoodIDs(["a", "b", "c", "d", "e"]), [
    "a",
    "b",
    "c",
    "d",
    "e",
  ]);
  assert.equal(MAX_ASSIGNED_STYLE_MOOD_COUNT, 5);
});

test("중복, 경로 문자, 5개 초과 무드 할당을 거부한다", () => {
  assert.throws(
    () => requiredStyleMoodIDs(["minimal", "minimal"]),
    HttpsError
  );
  assert.throws(() => requiredStyleMoodIDs(["group/minimal"]), HttpsError);
  assert.throws(
    () => requiredStyleMoodIDs(["a", "b", "c", "d", "e", "f"]),
    HttpsError
  );
});
