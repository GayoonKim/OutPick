import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRetainedExtractionEvidence,
  evidenceExpiresAt,
  evidenceShouldBeRetained,
  extractionEvidenceID,
  extractionEvidenceStoragePath,
  extractionIssueIdentity,
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
    stage: "seasonImageImport",
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
    stage: "seasonImageImport",
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
    jobPath: "brands/brand/importJobs/job",
    generation: 2,
    stage: "seasonImageImport" as const,
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
