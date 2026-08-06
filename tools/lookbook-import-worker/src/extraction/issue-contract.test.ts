import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  EXTRACTION_FAILURE_DISPOSITIONS,
  compareExtractionRuntimeVersions,
  encodeExtractionRuntimeVersion,
  encodeExtractionRuntimeVersionForStage,
  extractionIssueFingerprint,
  extractionIssueOccurrenceKey,
  extractionRuntimeVersionMatchesStage,
  extractionRuntimeVersionIsAtLeast,
  isExtractionIssueEligible,
  occurrenceEvidenceExpiresAt,
  type ExtractionIssueStage,
} from "./issue-contract.js";

type ContractFixture = {
  fingerprintCases: Array<{
    name: string;
    input: {
      stage: ExtractionIssueStage;
      platform: string | null;
      parserStrategy: string;
      failureReasons: string[];
      qualityReasons: string[];
      templateSignature: string;
      extractorVersion: string;
    };
    expectedFingerprint: string;
  }>;
  occurrenceCases: Array<{
    input: {jobPath: string; generation: number; evidenceID: string};
    expectedKey: string;
  }>;
};

const fixture = JSON.parse(readFileSync(path.resolve(
  process.cwd(),
  "../../contracts/lookbook-extraction-issue-v1.json",
), "utf8")) as ContractFixture;

test("로직 불충분만 issue 대상이다", () => {
  for (const disposition of EXTRACTION_FAILURE_DISPOSITIONS) {
    assert.equal(
      isExtractionIssueEligible(disposition),
      disposition === "extractionLogicInsufficient",
      disposition,
    );
  }
  assert.equal(isExtractionIssueEligible("unknown"), false);
});

test("두 stage fingerprint와 occurrence key가 golden 계약을 따른다", () => {
  for (const fixtureCase of fixture.fingerprintCases) {
    assert.equal(
      extractionIssueFingerprint(fixtureCase.input),
      fixtureCase.expectedFingerprint,
      fixtureCase.name,
    );
  }
  for (const fixtureCase of fixture.occurrenceCases) {
    assert.equal(
      extractionIssueOccurrenceKey(fixtureCase.input),
      fixtureCase.expectedKey,
    );
  }
});

test("host는 fingerprint 입력이 아니고 reason 순서는 결과를 바꾸지 않는다", () => {
  const input = fixture.fingerprintCases[0]?.input;
  assert.ok(input);
  assert.equal(
    extractionIssueFingerprint(input),
    extractionIssueFingerprint({
      ...input,
      failureReasons: [...input.failureReasons].reverse(),
    }),
  );
});

test("runtime version은 종류가 같은 경우에만 비교한다", () => {
  assert.equal(
    encodeExtractionRuntimeVersion({kind: "contract", value: 2}),
    "contract:2",
  );
  assert.equal(
    encodeExtractionRuntimeVersion({kind: "extractor", value: "1.10.0"}),
    "extractor:1.10.0",
  );
  assert.equal(
    compareExtractionRuntimeVersions("extractor:1.10.0", "extractor:1.2.9"),
    1,
  );
  assert.equal(
    compareExtractionRuntimeVersions("contract:2", "extractor:2.0.0"),
    null,
  );
  assert.equal(
    extractionRuntimeVersionIsAtLeast("contract:2", "extractor:2.0.0"),
    false,
  );
  assert.equal(
    encodeExtractionRuntimeVersionForStage({
      stage: "seasonDiscovery",
      value: 3,
    }),
    "contract:3",
  );
  assert.equal(
    encodeExtractionRuntimeVersionForStage({
      stage: "seasonImageImport",
      value: "2.1.0",
    }),
    "extractor:2.1.0",
  );
  assert.equal(
    extractionRuntimeVersionMatchesStage("seasonDiscovery", "contract:3"),
    true,
  );
  assert.equal(
    extractionRuntimeVersionMatchesStage(
      "seasonImageImport",
      "contract:3",
    ),
    false,
  );
});

test("occurrence evidence expiry는 7일이다", () => {
  assert.equal(
    occurrenceEvidenceExpiresAt(
      new Date("2026-08-05T00:00:00.000Z"),
    ).toISOString(),
    "2026-08-12T00:00:00.000Z",
  );
});
