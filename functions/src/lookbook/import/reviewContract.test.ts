import assert from "node:assert/strict";
import test from "node:test";
import {
  approvedCandidateKeys,
  nextGeneration,
  requiredReviewDecision,
} from "./reviewContract.js";

test("정상 승인과 오탐 제외 후보 계약을 검증한다", () => {
  assert.deepEqual(approvedCandidateKeys({
    decision: "approved",
    candidateKeys: ["a", "b"],
    excludedCandidateKeys: [],
  }), ["a", "b"]);
  assert.deepEqual(approvedCandidateKeys({
    decision: "approvedWithExclusions",
    candidateKeys: ["a", "b"],
    excludedCandidateKeys: ["a"],
  }), ["b"]);
  assert.throws(() => approvedCandidateKeys({
    decision: "approvedWithExclusions",
    candidateKeys: ["a"],
    excludedCandidateKeys: ["unknown"],
  }));
});

test("review decision과 generation을 검증한다", () => {
  assert.equal(
    requiredReviewDecision("insufficientImages"),
    "insufficientImages"
  );
  assert.throws(() => requiredReviewDecision("unknown"));
  assert.equal(nextGeneration(2), 3);
  assert.equal(nextGeneration(undefined), 1);
});
