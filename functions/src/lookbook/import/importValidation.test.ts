import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  blocksDuplicateSeasonImport,
  requiredDiagnosticType,
} from "./functions.js";

test("중복 season import를 막는 상태 계약을 유지한다", () => {
  for (const status of [
    "queued",
    "processing",
    "awaitingReview",
    "succeeded",
    "partialFailed",
  ]) {
    assert.equal(blocksDuplicateSeasonImport(status), true);
  }
  assert.equal(blocksDuplicateSeasonImport("failed"), false);
  assert.equal(blocksDuplicateSeasonImport(undefined), false);
});

test("지원하는 diagnostic type만 허용한다", () => {
  assert.equal(requiredDiagnosticType("season_discovery"), "season_discovery");
  assert.equal(
    requiredDiagnosticType("season_image_import"),
    "season_image_import"
  );
  assert.throws(() => requiredDiagnosticType("unknown"), HttpsError);
});
