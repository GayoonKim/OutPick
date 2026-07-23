import assert from "node:assert/strict";
import test from "node:test";

import {extractionResult, extractionResultWithStrategy} from "./core.js";
import {
  extractionCandidateKey,
  extractionSourceEvidence,
} from "./evidence.js";
import {
  CURRENT_EXTRACTION_VERSIONS,
  isReusableExtractionCache,
} from "./version.js";

test("후보마다 strategy와 마스킹된 source evidence를 연결한다", () => {
  const result = extractionResult({
    candidates: [{url: "https://cdn.example/look-1.jpg"}],
    strategy: "staticAnchors",
    rawCandidateCount: 1,
    sourceURL: "https://brand.example/archive?token=secret&cate_no=25",
    candidateKey: (candidate) => extractionCandidateKey(candidate.url),
  });

  assert.deepEqual(result.candidateEvidence, [{
    candidateKey: extractionCandidateKey("https://cdn.example/look-1.jpg"),
    strategy: "staticAnchors",
    sourceKind: "static_dom",
    source: extractionSourceEvidence(
      "https://brand.example/archive?token=other&cate_no=25",
    ),
  }]);
  assert.equal(
    JSON.stringify(result.candidateEvidence).includes("secret"),
    false,
  );
});

test("rendered 결과의 strategy와 source kind를 함께 갱신한다", () => {
  const initial = extractionResult({
    candidates: [{url: "https://cdn.example/look-1.jpg"}],
    strategy: "staticAnchors",
    rawCandidateCount: 1,
    sourceURL: "https://brand.example/archive",
    candidateKey: (candidate) => candidate.url,
  });
  const rendered = extractionResultWithStrategy(
    initial,
    "playwright:staticAnchors",
    "rendered_dom",
  );

  assert.equal(rendered.strategy, "playwright:staticAnchors");
  assert.equal(rendered.candidateEvidence[0]?.sourceKind, "rendered_dom");
  assert.equal(
    rendered.candidateEvidence[0]?.strategy,
    "playwright:staticAnchors",
  );
});

test("Generic extractor의 version 계약은 deterministic하다", () => {
  assert.deepEqual(CURRENT_EXTRACTION_VERSIONS, {
    extractorVersion: "1.2.0",
    platformAdapterKey: null,
    platformAdapterVersion: null,
    domainAdapterKey: null,
    domainAdapterVersion: null,
  });
});

test("현재 version과 완료된 hash 결과만 extraction cache로 재사용한다", () => {
  assert.equal(isReusableExtractionCache({
    candidateCount: 1,
    extractorVersion: "1.2.0",
    platformAdapterKey: "cafe24",
    platformAdapterVersion: "1.0.0",
    domainAdapterKey: null,
    domainAdapterVersion: null,
    qualityStatus: "needsReview",
    contentHashResolutionComplete: true,
  }), true);
  assert.equal(isReusableExtractionCache({
    candidateCount: 1,
    extractorVersion: "1.1.0",
    platformAdapterKey: "cafe24",
    platformAdapterVersion: "1.0.0",
    domainAdapterKey: null,
    domainAdapterVersion: null,
    qualityStatus: "accepted",
    contentHashResolutionComplete: true,
  }), false);
  assert.equal(isReusableExtractionCache({
    candidateCount: 1,
    extractorVersion: "1.2.0",
    platformAdapterKey: "cafe24",
    platformAdapterVersion: "0.9.0",
    domainAdapterKey: null,
    domainAdapterVersion: null,
    qualityStatus: "accepted",
    contentHashResolutionComplete: true,
  }), false);
  assert.equal(isReusableExtractionCache({
    candidateCount: 1,
    extractorVersion: "1.2.0",
    platformAdapterKey: null,
    platformAdapterVersion: null,
    domainAdapterKey: null,
    domainAdapterVersion: null,
    qualityStatus: "accepted",
    contentHashResolutionComplete: false,
  }), false);
});
