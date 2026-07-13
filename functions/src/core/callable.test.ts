/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredAuthUID,
  requiredBoolean,
  requiredDocumentID,
  requiredString,
} from "./callable.js";

function assertHttpsError(
  work: () => unknown,
  code: HttpsError["code"],
  message: string
): void {
  assert.throws(work, (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}

test("recordData는 plain object만 허용한다", () => {
  const value = {name: "OutPick"};
  assert.equal(recordData(value), value);
  for (const invalid of [null, [], "value", 1, true]) {
    assertHttpsError(
      () => recordData(invalid),
      "invalid-argument",
      "요청 데이터가 올바르지 않습니다."
    );
  }
});

test("requiredString은 trim과 길이 계약을 유지한다", () => {
  assert.equal(requiredString({name: "  OutPick  "}, "name", 7), "OutPick");
  assertHttpsError(
    () => requiredString({}, "name", 10),
    "invalid-argument",
    "name 값이 필요합니다."
  );
  assertHttpsError(
    () => requiredString({name: "   "}, "name", 10),
    "invalid-argument",
    "name 값이 올바르지 않습니다."
  );
});

test("optionalString은 누락과 빈 문자열을 null로 정규화한다", () => {
  assert.equal(optionalString({}, "memo", 5), null);
  assert.equal(optionalString({memo: null}, "memo", 5), null);
  assert.equal(optionalString({memo: "  "}, "memo", 5), null);
  assert.equal(optionalString({memo: " ok "}, "memo", 5), "ok");
  assertHttpsError(
    () => optionalString({memo: "123456"}, "memo", 5),
    "invalid-argument",
    "memo 값이 너무 깁니다."
  );
});

test("boolean, auth UID와 document ID 오류 계약을 유지한다", () => {
  assert.equal(requiredBoolean({enabled: true}, "enabled"), true);
  assert.equal(requiredAuthUID("user-id"), "user-id");
  assert.equal(requiredDocumentID(" brand-id ", "brandID"), "brand-id");
  assert.equal(optionalDocumentID(null, "brandID"), null);
  assertHttpsError(
    () => requiredBoolean({enabled: "true"}, "enabled"),
    "invalid-argument",
    "enabled 값이 필요합니다."
  );
  assertHttpsError(
    () => requiredAuthUID(undefined),
    "unauthenticated",
    "로그인이 필요합니다."
  );
  assertHttpsError(
    () => requiredDocumentID("brands/id", "brandID"),
    "invalid-argument",
    "brandID 값이 올바르지 않습니다."
  );
});
