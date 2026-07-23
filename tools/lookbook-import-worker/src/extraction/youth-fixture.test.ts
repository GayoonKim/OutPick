import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";

import {
  extractionResultWithStrategy,
  mergeExtractionResults,
} from "./core.js";
import {
  canonicalCandidateURL,
  dedupeCandidatesByContentHash,
  imageContentHash,
  resolveContentHashDedupe,
} from "./dedupe.js";
import {collectExpectedCountEvidence} from "./expected-count.js";
import {detectProgrammaticGallery} from "./programmatic-gallery.js";
import {evaluateExtractionQuality} from "./quality.js";
import {expandExpectedCandidates} from "../fixture/differential.js";
import type {FixtureExpected} from "../fixture/types.js";
import {
  extractImageCandidates,
  fallbackReasonForExtraction,
} from "../processor.js";

const fixtureDirectory = join(
  process.cwd(),
  "fixtures/season-images/incidents/youth-programmatic-gallery",
);
const sourceURL =
  "https://youth-lab.kr/page/collection_detail.html?" +
  "product_no=6052&cate_no=25&display_group=1";

test("YOUTH programmatic gallery는 rendered fallback과 검토 대상이다", async () => {
  const [staticHTML, renderedHTML, expectedText] = await Promise.all([
    readFile(join(fixtureDirectory, "input.html"), "utf8"),
    readFile(join(fixtureDirectory, "rendered.html"), "utf8"),
    readFile(join(fixtureDirectory, "expected.json"), "utf8"),
  ]);
  const expected = JSON.parse(expectedText) as FixtureExpected;
  const staticExtraction = extractImageCandidates(staticHTML, sourceURL);
  const renderedExtraction = extractImageCandidates(renderedHTML, sourceURL);
  const countEvidence = collectExpectedCountEvidence(
    staticHTML,
    sourceURL,
    staticExtraction.candidates.length,
  );
  const programmaticEvidence = detectProgrammaticGallery(staticHTML);

  assert.equal(
    staticExtraction.candidates.length,
    1,
  );
  assert.equal(staticExtraction.strategy, "cafe24ProductAdditional");
  assert.equal(
    renderedExtraction.candidates.length,
    45,
  );
  assert.equal(renderedExtraction.strategy, "lookbookContent");
  assert.deepEqual(countEvidence.map((item) => item.value), [45, 46]);
  assert.deepEqual(countEvidence.map((item) => item.kind), [
    "declared_script_total",
    "scoped_gallery_candidate_total",
  ]);
  assert.equal(programmaticEvidence.detected, true);
  assert.equal(
    fallbackReasonForExtraction(
      staticExtraction,
      staticHTML,
      programmaticEvidence,
    ),
    "programmaticGallerySignals",
  );

  const renderedResult = extractionResultWithStrategy(
    renderedExtraction,
    "playwright:lookbookContent",
    "rendered_dom",
  );
  const merged = mergeExtractionResults({
    results: [staticExtraction, renderedResult],
    strategy: "playwright:lookbookContent+staticMerge",
    candidateKey: (candidate) => canonicalCandidateURL(candidate.sourceURL),
  });
  assert.equal(
    merged.candidates.length,
    expandExpectedCandidates(expected.candidates).length,
  );
  assert.equal(merged.candidateEvidence[0]?.sourceKind, "static_dom");
  assert.equal(merged.candidateEvidence[1]?.sourceKind, "rendered_dom");

  const staticQuality = evaluateExtractionQuality({
    candidateCount: staticExtraction.candidates.length,
    rawCandidateCount: staticExtraction.rawCandidateCount,
    staticCandidateCount: staticExtraction.candidates.length,
    renderedCandidateCount: null,
    expectedCountEvidence: countEvidence,
    programmaticGalleryDetected: true,
  });
  assert.equal(staticQuality.status, "needsReview");
  assert.deepEqual(staticQuality.reasons, ["expected_count_mismatch"]);

  const renderedQuality = evaluateExtractionQuality({
    candidateCount: merged.candidates.length,
    rawCandidateCount: merged.rawCandidateCount,
    staticCandidateCount: staticExtraction.candidates.length,
    renderedCandidateCount: renderedExtraction.candidates.length,
    expectedCountEvidence: countEvidence,
    programmaticGalleryDetected: true,
  });
  assert.deepEqual(renderedQuality, {status: "accepted", reasons: []});
});

test("YOUTH 활성 grid evidence는 다른 시즌 total을 제외한다", () => {
  const summerHTML = `
    <ul id="lookbookGrid3"></ul>
    <script>
      const GRID_CONFIG = {
        lookbookGrid: { total: 75 },
        lookbookGrid2: { total: 45 },
        lookbookGrid3: { total: 42 }
      };
    </script>
  `;
  const evidence = collectExpectedCountEvidence(
    summerHTML,
    "https://youth-lab.kr/page/collection_detail.html?product_no=6159",
    7,
  );

  assert.deepEqual(evidence.map((item) => item.value), [42, 49]);
  assert.equal(evidence.some((item) => item.value === 75), false);

  const alreadyRendered = collectExpectedCountEvidence(
    summerHTML.replace(
      "<ul id=\"lookbookGrid3\"></ul>",
      "<ul id=\"lookbookGrid3\"><li><img src=\"/look-1.jpg\"></li></ul>",
    ),
    "https://youth-lab.kr/page/collection_detail.html?product_no=6159",
    7,
  );
  assert.deepEqual(alreadyRendered.map((item) => item.value), [42]);
});

test("content hash dedupe는 source 후보 수와 최종 고유 수를 분리한다", async () => {
  const renderedHTML = await readFile(
    join(fixtureDirectory, "rendered.html"),
    "utf8",
  );
  const staticHTML = await readFile(
    join(fixtureDirectory, "input.html"),
    "utf8",
  );
  const candidates = [
    ...extractImageCandidates(staticHTML, sourceURL).candidates,
    ...extractImageCandidates(renderedHTML, sourceURL).candidates,
  ];
  const hashes = new Map<string, string>();
  candidates.forEach((candidate, index) => {
    const bytes = index === 1 ? "same-as-hero" : `image-${index}`;
    const normalizedBytes = index === 0 ? "same-as-hero" : bytes;
    hashes.set(
      canonicalCandidateURL(candidate.sourceURL),
      imageContentHash(Buffer.from(normalizedBytes)),
    );
  });

  assert.equal(candidates.length, 46);
  assert.equal(dedupeCandidatesByContentHash(candidates, hashes).length, 45);

  const resolved = await resolveContentHashDedupe({
    candidates,
    concurrency: 3,
    loadBytes: async (candidate) => Buffer.from(
      /ss26-hero|\/sep\/1\.jpg/.test(candidate.sourceURL) ?
        "same-as-hero" :
        candidate.sourceURL,
    ),
  });
  assert.equal(resolved.complete, true);
  assert.equal(resolved.sourceCandidateCount, 46);
  assert.equal(resolved.contentHashCandidateCount, 45);

  const partial = await resolveContentHashDedupe({
    candidates: candidates.slice(0, 2),
    loadBytes: async (candidate) =>
      candidate.sourceURL.includes("ss26-hero") ? null : Buffer.from("gallery"),
  });
  assert.equal(partial.complete, false);
  assert.equal(partial.failureCount, 1);
  assert.equal(partial.candidates.length, 2);
});

test("예상 수를 알 수 없는 실제 1장 strong section은 검토한다", () => {
  const quality = evaluateExtractionQuality({
    candidateCount: 1,
    rawCandidateCount: 1,
    staticCandidateCount: 1,
    renderedCandidateCount: null,
    expectedCountEvidence: [],
    programmaticGalleryDetected: false,
  });
  assert.deepEqual(quality, {
    status: "needsReview",
    reasons: ["expected_count_unverified"],
  });

  const incompleteHash = evaluateExtractionQuality({
    candidateCount: 1,
    rawCandidateCount: 1,
    staticCandidateCount: 1,
    renderedCandidateCount: null,
    expectedCountEvidence: [],
    programmaticGalleryDetected: false,
    contentHashComplete: false,
  });
  assert.deepEqual(incompleteHash, {
    status: "needsReview",
    reasons: ["expected_count_unverified", "content_hash_incomplete"],
  });
});

test("예상 수 일치와 불일치, 예상 수 없는 filter drop을 분류한다", () => {
  const matched = evaluateExtractionQuality({
    candidateCount: 24,
    rawCandidateCount: 72,
    staticCandidateCount: 24,
    renderedCandidateCount: null,
    expectedCountEvidence: [{
      kind: "declared_script_total",
      value: 24,
      confidence: 0.82,
      sourceFingerprint: "fixture",
    }],
    programmaticGalleryDetected: false,
  });
  assert.deepEqual(matched, {status: "accepted", reasons: []});

  const mismatch = evaluateExtractionQuality({
    candidateCount: 44,
    rawCandidateCount: 44,
    staticCandidateCount: 1,
    renderedCandidateCount: 44,
    expectedCountEvidence: [{
      kind: "declared_script_total",
      value: 45,
      confidence: 0.82,
      sourceFingerprint: "fixture",
    }],
    programmaticGalleryDetected: true,
  });
  assert.equal(mismatch.reasons.includes("expected_count_mismatch"), true);

  const unexplainedDelta = evaluateExtractionQuality({
    candidateCount: 8,
    rawCandidateCount: 8,
    staticCandidateCount: 1,
    renderedCandidateCount: 8,
    expectedCountEvidence: [],
    programmaticGalleryDetected: false,
  });
  assert.deepEqual(unexplainedDelta.reasons, [
    "expected_count_unverified",
  ]);

  const filterDrop = evaluateExtractionQuality({
    candidateCount: 2,
    rawCandidateCount: 12,
    staticCandidateCount: 2,
    renderedCandidateCount: null,
    expectedCountEvidence: [],
    programmaticGalleryDetected: false,
  });
  assert.deepEqual(filterDrop.reasons, ["expected_count_unverified"]);
});
