/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  canonicalBrandName,
  normalizedBrandName,
  normalizedHTTPURL,
} from "../../shared/brandValidation.js";
import {
  normalizedEmail,
  optionalHTTPURLPatch,
  requiredBrandManagerRole,
  validateBrandLogoPath,
} from "./functions.js";

test("브랜드 이름과 URL을 canonical 값으로 정규화한다", () => {
  assert.equal(canonicalBrandName("  OUT   PICK  "), "OUT PICK");
  assert.equal(normalizedBrandName("  OUT   PICK  "), "out pick");
  assert.equal(normalizedHTTPURL("Example.COM/lookbook", "url"),
    "https://example.com/lookbook");
});

test("email, manager role과 URL patch 계약을 유지한다", () => {
  assert.equal(normalizedEmail(" USER@Example.COM "), "user@example.com");
  assert.equal(requiredBrandManagerRole("owner"), "owner");
  assert.equal(optionalHTTPURLPatch({}, "websiteURL"), undefined);
  assert.equal(optionalHTTPURLPatch({websiteURL: " "}, "websiteURL"), null);
  assert.throws(() => normalizedEmail("invalid"), HttpsError);
  assert.throws(() => requiredBrandManagerRole("viewer"), HttpsError);
});

test("logo path는 요청 브랜드의 고정 경로만 허용한다", () => {
  validateBrandLogoPath("brand-1", null, "thumb.jpg");
  validateBrandLogoPath(
    "brand-1",
    "brands/brand-1/logo/thumb.jpg",
    "thumb.jpg"
  );
  assert.throws(
    () => validateBrandLogoPath(
      "brand-1",
      "brands/brand-2/logo/thumb.jpg",
      "thumb.jpg"
    ),
    HttpsError
  );
});
