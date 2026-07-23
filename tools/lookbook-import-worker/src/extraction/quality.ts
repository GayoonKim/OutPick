import type {ExpectedCountEvidence} from "./expected-count.js";

export type ExtractionQualityStatus = "accepted" | "needsReview" | "failed";

export type ExtractionQualityReason =
  | "no_candidates"
  | "programmatic_gallery_requires_review"
  | "expected_count_unverified"
  | "expected_count_mismatch"
  | "large_rendered_delta_without_expected_evidence"
  | "raw_candidate_drop"
  | "content_hash_incomplete";

export type ExtractionQuality = {
  status: ExtractionQualityStatus;
  reasons: ExtractionQualityReason[];
};

export function evaluateExtractionQuality(input: {
  candidateCount: number;
  rawCandidateCount: number;
  staticCandidateCount: number;
  renderedCandidateCount: number | null;
  expectedCountEvidence: ExpectedCountEvidence[];
  programmaticGalleryDetected: boolean;
  contentHashComplete?: boolean;
}): ExtractionQuality {
  if (input.candidateCount === 0) {
    return {status: "failed", reasons: ["no_candidates"]};
  }

  const reasons: ExtractionQualityReason[] = [];
  const expectedCounts = input.expectedCountEvidence.map((item) => item.value);

  if (expectedCounts.length === 0) {
    reasons.push("expected_count_unverified");
  } else if (!expectedCounts.includes(input.candidateCount)) {
    reasons.push("expected_count_mismatch");
  }
  if (input.contentHashComplete === false) {
    reasons.push("content_hash_incomplete");
  }

  return {
    status: reasons.length === 0 ? "accepted" : "needsReview",
    reasons: Array.from(new Set(reasons)),
  };
}
