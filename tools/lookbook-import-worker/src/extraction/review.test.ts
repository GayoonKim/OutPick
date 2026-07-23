import assert from "node:assert/strict";
import test from "node:test";

import {
  extractionStructureTokens,
  makeReviewContract,
  reviewDisposition,
  trustCanAutoApprove,
} from "./review.js";
import {CURRENT_EXTRACTION_VERSIONS} from "./version.js";
import type {ProgrammaticGalleryEvidence} from "./programmatic-gallery.js";

const sourceURL = "https://brand.example/archive/2026";
const evidence = [{
  kind: "declared_script_total" as const,
  value: 2,
  confidence: 0.82,
  sourceFingerprint: "source",
}];
const programmatic: ProgrammaticGalleryEvidence = {
  detected: true,
  signals: [
    "declared_total",
    "creates_image_element",
    "assigns_image_source",
    "appends_image",
  ],
};

test("review snapshot과 trust baseline ID는 결정적이다", () => {
  const input = {
    brandID: "brand-1",
    sourceURL,
    strategy: "playwright:lookbookContent+staticMerge",
    candidateKeys: ["a", "b"],
    expectedCountEvidence: evidence,
    programmaticGalleryEvidence: programmatic,
    quality: {
      status: "needsReview" as const,
      reasons: ["programmatic_gallery_requires_review" as const],
    },
    renderedCandidateCount: 2,
    contentHashComplete: true,
    versions: CURRENT_EXTRACTION_VERSIONS,
  };
  assert.deepEqual(makeReviewContract(input), makeReviewContract(input));
  assert.equal(makeReviewContract(input).trustEligible, true);
});

test("위험 reason은 기존 trust로 자동 승인할 수 없다", () => {
  assert.equal(trustCanAutoApprove({
    status: "needsReview",
    reasons: ["expected_count_mismatch"],
  }, true), false);
  assert.equal(trustCanAutoApprove({
    status: "needsReview",
    reasons: ["programmatic_gallery_requires_review"],
  }, true), true);
});

test("template structure token은 관련 container만 정규화한다", () => {
  assert.deepEqual(
    extractionStructureTokens(
      "<div class=\"xans-product-additional random\">" +
      "<section id=\"lookbookGallery\"></section></div>",
    ),
    ["lookbookgallery", "xans-product-additional"],
  );
});

test("첫 signature는 멈추고 신뢰된 안전 signature만 materialize한다", () => {
  const quality = {
    status: "accepted" as const,
    reasons: [],
  };
  assert.equal(reviewDisposition({
    trusted: false,
    quality,
    trustEligible: true,
  }), "awaitingReview");
  assert.equal(reviewDisposition({
    trusted: true,
    quality,
    trustEligible: true,
  }), "materialize");
});
