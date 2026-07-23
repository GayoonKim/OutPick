import assert from "node:assert/strict";
import test from "node:test";
import {
  deterministicAssetRetryTaskID,
  deterministicImportTaskID,
  diagnosticCandidateID,
} from "./functions.js";

test("import task ID는 동일 입력에 대해 결정적이다", () => {
  const first = deterministicImportTaskID("brand-1", "job-1", 0);
  const second = deterministicImportTaskID("brand-1", "job-1", 0);
  assert.equal(first, second);
  assert.match(first, /^import-/);
  assert.ok(first.length <= 500);
  assert.notEqual(
    first,
    deterministicImportTaskID("brand-1", "job-1", 1)
  );
});

test("asset retry와 diagnostic candidate ID도 입력 계약을 반영한다", () => {
  const retry = deterministicAssetRetryTaskID(
    "brand-1",
    "season-1",
    "job-1",
    "request-1"
  );
  assert.match(retry, /^asset-retry-/);
  assert.ok(retry.length <= 500);
  assert.equal(
    diagnosticCandidateID("https://example.com/season/1"),
    diagnosticCandidateID("https://example.com/season/1")
  );
});
