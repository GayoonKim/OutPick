import assert from "node:assert/strict";
import test from "node:test";

import {
  extractionAdapterIdentity,
  imageExtractionIssueDisposition,
  nextIssueClusterOccurrence,
  representativeEvidenceScore,
  seasonDiscoveryIssueDisposition,
  shouldReplaceRepresentativeEvidence,
} from "./issue-policy.js";
import {buildRetainedExtractionEvidence} from "./retained-evidence.js";
import {CURRENT_EXTRACTION_VERSIONS} from "./version.js";

function evidence(input: {
  failureReasons?: string[];
  qualityReasons?: Array<
    | "no_candidates"
    | "programmatic_gallery_requires_review"
    | "expected_count_unverified"
    | "expected_count_mismatch"
    | "large_rendered_delta_without_expected_evidence"
    | "raw_candidate_drop"
    | "content_hash_incomplete"
  >;
}) {
  return buildRetainedExtractionEvidence({
    status: "needsReview",
    stage: "seasonImageImport",
    sourceURL: "https://brand.example/lookbook",
    strategy: "mainContent",
    failureReasons: input.failureReasons,
    qualityReasons: input.qualityReasons,
    templateSignature: "template",
    versions: CURRENT_EXTRACTION_VERSIONS,
  });
}

test("예상 수 미확인 단독은 issue가 아니고 확정 불충분만 issue다", () => {
  assert.equal(imageExtractionIssueDisposition(evidence({
    qualityReasons: ["expected_count_unverified"],
  })), "identityReview");
  assert.equal(imageExtractionIssueDisposition(evidence({
    qualityReasons: ["programmatic_gallery_requires_review"],
  })), "identityReview");
  assert.equal(imageExtractionIssueDisposition(evidence({
    qualityReasons: ["expected_count_mismatch"],
  })), "extractionLogicInsufficient");
  assert.equal(imageExtractionIssueDisposition(evidence({
    failureReasons: ["retry_exhausted"],
  })), "transientInfrastructure");
});

test("시즌 discovery는 미해결 확장과 최종 후보 부족만 issue다", () => {
  assert.equal(seasonDiscoveryIssueDisposition({
    failureReasons: ["dynamic_rendering_detected"],
    unresolvedExpansion: false,
  }), "identityReview");
  assert.equal(seasonDiscoveryIssueDisposition({
    failureReasons: ["load_more_detected"],
    unresolvedExpansion: true,
  }), "extractionLogicInsufficient");
  assert.equal(seasonDiscoveryIssueDisposition({
    failureReasons: ["worker_timeout"],
    unresolvedExpansion: false,
  }), "transientInfrastructure");
});

test("adapter identity는 domain, platform, generic 순으로 선택한다", () => {
  assert.deepEqual(extractionAdapterIdentity({
    ...CURRENT_EXTRACTION_VERSIONS,
    platformAdapterKey: "cafe24",
    domainAdapterKey: "brand-a",
  }), {scope: "domain", key: "brand-a"});
  assert.deepEqual(extractionAdapterIdentity({
    ...CURRENT_EXTRACTION_VERSIONS,
    platformAdapterKey: "cafe24",
  }), {scope: "platform", key: "cafe24"});
  assert.deepEqual(
    extractionAdapterIdentity(CURRENT_EXTRACTION_VERSIONS),
    {scope: "generic", key: "generic"},
  );
});

test("대표 evidence는 schema와 정보 tuple이 더 큰 경우만 교체한다", () => {
  const candidate = representativeEvidenceScore(evidence({
    qualityReasons: ["expected_count_mismatch"],
  }));
  assert.equal(shouldReplaceRepresentativeEvidence({
    status: "missing",
    previousScore: candidate,
    candidateScore: candidate,
  }), true);
  assert.equal(shouldReplaceRepresentativeEvidence({
    status: "ready",
    previousScore: candidate,
    candidateScore: candidate,
  }), false);
  assert.equal(shouldReplaceRepresentativeEvidence({
    status: "ready",
    previousScore: {...candidate, schemaVersion: 0},
    candidateScore: candidate,
  }), true);
});

test("terminal 재발만 open으로 돌리고 active occurrence는 상태를 보존한다", () => {
  assert.deepEqual(nextIssueClusterOccurrence({
    previous: {status: "inProgress", stateVersion: 3, occurrenceCount: 4},
    runtimeVersion: "extractor:2.0.0",
  }), {
    status: "inProgress",
    stateVersion: 3,
    occurrenceCount: 5,
    recurrenceCount: 0,
    isRecurrence: false,
    clearExpiresAt: false,
  });
  assert.equal(nextIssueClusterOccurrence({
    previous: {
      status: "verified",
      stateVersion: 5,
      occurrenceCount: 7,
      recurrenceCount: 1,
      fixedRuntimeVersion: "extractor:2.0.0",
    },
    runtimeVersion: "extractor:2.1.0",
  }).status, "open");
});
