import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRetainedExtractionEvidence,
  evidenceExpiresAt,
  evidenceShouldBeRetained,
  extractionEvidenceID,
  extractionEvidenceStoragePath,
  extractionIssueIdentity,
  nextExtractionIssueClusterState,
  versionIsAtLeast,
} from "./retained-evidence.js";
import {CURRENT_EXTRACTION_VERSIONS} from "./version.js";

test("failed와 needsReview만 evidence 저장 대상이다", () => {
  assert.equal(evidenceShouldBeRetained("accepted"), false);
  assert.equal(evidenceShouldBeRetained("needsReview"), true);
  assert.equal(evidenceShouldBeRetained("failed"), true);
});

test("최소 DOM evidence는 URL value와 script/cookie를 보존하지 않는다", () => {
  const evidence = buildRetainedExtractionEvidence({
    status: "needsReview",
    stage: "parsing",
    sourceURL: "https://brand.example/lookbook?token=source-secret",
    html: [
      "<script>const token = 'script-secret';" +
        "const html = '<img src=\"/script.jpg?" +
        "token=inside-script\">';</script>",
      "<section id=\"gallery\" class=\"lookbook private-class\">",
      "<img data-src=\"/one.jpg?auth=image-secret\" ",
      "alt=\"  첫 번째   룩  \">",
      "<a href=\"/next?access_token=link-secret\">다음</a>",
      "</section>",
    ].join(""),
    strategy: "mainContent",
    qualityReasons: ["expected_count_mismatch"],
    templateSignature: "template",
    versions: CURRENT_EXTRACTION_VERSIONS,
  });
  const serialized = JSON.stringify(evidence);

  assert.equal(serialized.includes("source-secret"), false);
  assert.equal(serialized.includes("script-secret"), false);
  assert.equal(serialized.includes("inside-script"), false);
  assert.equal(serialized.includes("image-secret"), false);
  assert.equal(serialized.includes("link-secret"), false);
  assert.equal(serialized.includes("<script"), false);
  assert.deepEqual(evidence.source.queryKeys, ["token"]);
  assert.equal(evidence.elements.some((item) => item.tag === "img"), true);
  assert.equal(evidence.elements.some((item) => item.text === "첫 번째 룩"), true);
});

test("issue fingerprint는 순서와 무관하고 signature를 분리한다", () => {
  const base = buildRetainedExtractionEvidence({
    status: "needsReview",
    stage: "parsing",
    sourceURL: "https://brand.example/lookbook",
    strategy: "mainContent",
    failureReasons: ["b", "a"],
    qualityReasons: ["raw_candidate_drop", "expected_count_mismatch"],
    templateSignature: "template-a",
    versions: CURRENT_EXTRACTION_VERSIONS,
  });
  const reordered: typeof base = {
    ...base,
    failureReasons: ["a", "b"],
    qualityReasons: [
      "expected_count_mismatch",
      "raw_candidate_drop",
    ],
  };
  const changed = {...base, templateSignature: "template-b"};

  assert.equal(
    extractionIssueIdentity(base).fingerprint,
    extractionIssueIdentity(reordered).fingerprint,
  );
  assert.notEqual(
    extractionIssueIdentity(base).fingerprint,
    extractionIssueIdentity(changed).fingerprint,
  );
});

test("evidence ID와 경로, 7일 expiry가 결정적이다", () => {
  const input = {
    brandID: "brand",
    jobID: "job",
    dispatchGeneration: 2,
    stage: "parsing",
    fingerprint: "a".repeat(40),
  };
  const evidenceID = extractionEvidenceID(input);
  assert.equal(evidenceID, extractionEvidenceID(input));
  assert.match(
    extractionEvidenceStoragePath(evidenceID),
    /^lookbook-extraction-evidence\//,
  );
  assert.equal(
    evidenceExpiresAt(new Date("2026-07-23T00:00:00.000Z")).toISOString(),
    "2026-07-30T00:00:00.000Z",
  );
});

test("fixed version 이후 재발 여부를 semver 숫자로 비교한다", () => {
  assert.equal(versionIsAtLeast("1.10.0", "1.2.0"), true);
  assert.equal(versionIsAtLeast("1.1.9", "1.2.0"), false);
  assert.equal(versionIsAtLeast("2.0.0", "1.9.9"), true);
});

test("같은 cluster 재발은 occurrence와 fixed 이후 recurrence를 증가시킨다", () => {
  const first = nextExtractionIssueClusterState({
    sourceHost: "brand.example",
    evidenceID: "a".repeat(40),
    extractorVersion: "1.1.0",
  });
  const second = nextExtractionIssueClusterState({
    previous: {
      ...first,
      fixedInExtractorVersion: "1.1.0",
      status: "fixed",
    },
    sourceHost: "other.example",
    evidenceID: "b".repeat(40),
    extractorVersion: "1.2.0",
  });

  assert.equal(second.occurrenceCount, 2);
  assert.equal(second.affectedDomainCount, 2);
  assert.equal(second.recurrenceCount, 1);
  assert.equal(second.isRecurrence, true);
  assert.equal(second.status, "open");
});
