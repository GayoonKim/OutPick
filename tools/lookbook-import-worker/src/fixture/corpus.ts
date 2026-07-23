import {
  extractionResultWithStrategy,
  mergeExtractionResults,
} from "../extraction/core.js";
import {canonicalCandidateURL} from "../extraction/dedupe.js";
import {collectExpectedCountEvidence} from "../extraction/expected-count.js";
import {detectProgrammaticGallery} from "../extraction/programmatic-gallery.js";
import {evaluateExtractionQuality} from "../extraction/quality.js";
import {extractImageCandidates} from "../processor.js";
import {extractSeasonCandidateResult} from "../season-discovery.js";
import {
  differentialIsEmpty,
  expectedSnapshot,
  expandExpectedCandidates,
  fixtureDifferential,
} from "./differential.js";
import {loadFixtureCorpus} from "./manifest.js";
import type {
  FixtureCase,
  FixtureEvaluation,
  FixtureSnapshot,
} from "./types.js";

export async function evaluateFixtureCorpus(
  root: string,
): Promise<FixtureEvaluation[]> {
  const fixtures = await loadFixtureCorpus(root);
  return fixtures.map(evaluateFixtureCase);
}

export function evaluateFixtureCase(fixture: FixtureCase): FixtureEvaluation {
  const current = fixture.metadata.kind === "discovery" ?
    discoverySnapshot(fixture) :
    seasonImageSnapshot(fixture);
  const baseline = expectedSnapshot(fixture.expected);
  const differential = fixtureDifferential(baseline, current);
  const expectedCandidates = expandExpectedCandidates(
    fixture.expected.candidates,
  );
  const errors: string[] = [];

  fixture.expected.negativeCandidateKeys.forEach((key) => {
    if (current.candidateKeys.includes(key)) {
      errors.push(`negative 후보가 추출됐습니다: ${key}`);
    }
  });

  if (fixture.expected.orderPolicy === "strict") {
    if (!differentialIsEmpty(differential)) {
      errors.push("strict golden snapshot과 현재 결과가 다릅니다.");
    }
  } else {
    const expectedKeys = expectedCandidates.map((candidate) => candidate.key);
    const missingKeys = expectedKeys.filter((key) =>
      !current.candidateKeys.includes(key));
    if (missingKeys.length > 0) {
      errors.push(`필수 positive 후보 누락: ${missingKeys.join(", ")}`);
    }
    if (!isOrderedSubsequence(expectedKeys, current.candidateKeys)) {
      errors.push("relative 후보 순서가 바뀌었습니다.");
    }
    if (
      differential.strategyChange !== null ||
      differential.adapterChange !== null ||
      differential.qualityChange !== null ||
      differential.titleChanges.length > 0
    ) {
      errors.push("strategy/adapter/quality/title golden 계약이 다릅니다.");
    }
  }

  return {
    fixtureID: fixture.metadata.id,
    passed: errors.length === 0,
    errors,
    differential,
    current,
  };
}

function discoverySnapshot(fixture: FixtureCase): FixtureSnapshot {
  const extraction = extractSeasonCandidateResult(
    fixture.inputHTML,
    fixture.metadata.sourceURL,
  );
  return {
    candidateKeys: extraction.candidates.map(
      (candidate) => candidate.seasonURL,
    ),
    candidateTitles: Object.fromEntries(extraction.candidates.map((candidate) =>
      [candidate.seasonURL, candidate.title])),
    strategy: extraction.strategy,
    adapter: {
      platformKey: extraction.versions.platformAdapterKey,
      domainKey: extraction.versions.domainAdapterKey,
    },
    quality: null,
  };
}

function seasonImageSnapshot(fixture: FixtureCase): FixtureSnapshot {
  const staticExtraction = extractImageCandidates(
    fixture.inputHTML,
    fixture.metadata.sourceURL,
  );
  const expectedCountEvidence = collectExpectedCountEvidence(
    fixture.inputHTML,
    fixture.metadata.sourceURL,
  );
  const programmatic = detectProgrammaticGallery(fixture.inputHTML);
  const renderedExtraction = fixture.renderedHTML === null ?
    null :
    extractImageCandidates(fixture.renderedHTML, fixture.metadata.sourceURL);
  const selectedExtraction =
    renderedExtraction !== null &&
    renderedExtraction.candidates.length > staticExtraction.candidates.length ?
      mergeExtractionResults({
        results: [
          staticExtraction,
          extractionResultWithStrategy(
            renderedExtraction,
            `playwright:${renderedExtraction.strategy}`,
            "rendered_dom",
          ),
        ],
        strategy: `playwright:${renderedExtraction.strategy}+staticMerge`,
        candidateKey: (candidate) => canonicalCandidateURL(candidate.sourceURL),
      }) :
      staticExtraction;
  const quality = evaluateExtractionQuality({
    candidateCount: selectedExtraction.candidates.length,
    rawCandidateCount: selectedExtraction.rawCandidateCount,
    staticCandidateCount: staticExtraction.candidates.length,
    renderedCandidateCount: renderedExtraction?.candidates.length ?? null,
    expectedCountEvidence,
    programmaticGalleryDetected: programmatic.detected,
    contentHashComplete: true,
  });
  return {
    candidateKeys: selectedExtraction.candidates.map((candidate) =>
      canonicalCandidateURL(candidate.sourceURL)),
    candidateTitles: {},
    strategy: selectedExtraction.strategy,
    adapter: {
      platformKey: selectedExtraction.versions.platformAdapterKey,
      domainKey: selectedExtraction.versions.domainAdapterKey,
    },
    quality,
  };
}

function isOrderedSubsequence(expected: string[], actual: string[]): boolean {
  let expectedIndex = 0;
  actual.forEach((key) => {
    if (key === expected[expectedIndex]) {
      expectedIndex += 1;
    }
  });
  return expectedIndex === expected.length;
}
