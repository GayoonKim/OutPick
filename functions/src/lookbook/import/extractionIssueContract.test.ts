import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  EXTRACTION_FAILURE_DISPOSITIONS,
  compareExtractionRuntimeVersions,
  encodeExtractionRuntimeVersion,
  encodeExtractionRuntimeVersionForStage,
  extractionIssueExpiresAt,
  extractionIssueFingerprint,
  extractionIssueOccurrenceKey,
  extractionRuntimeVersionMatchesStage,
  extractionRuntimeVersionIsAtLeast,
  isExtractionIssueEligible,
  isExtractionFixRetryEligible,
  occurrenceEvidenceExpiresAt,
  resolveExtractionIssueOccurrence,
  terminalExtractionJobExpiresAt,
  transitionExtractionIssueState,
  type ExtractionIssueStage,
  type ExtractionIssueAction,
  type ExtractionIssueStatus,
} from "./extractionIssueContract.js";

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
  "../contracts/lookbook-extraction-issue-v1.json"
), "utf8")) as ContractFixture;

test("로직 불충분만 issue 대상이다", () => {
  for (const disposition of EXTRACTION_FAILURE_DISPOSITIONS) {
    assert.equal(
      isExtractionIssueEligible(disposition),
      disposition === "extractionLogicInsufficient",
      disposition
    );
  }
  assert.equal(isExtractionIssueEligible("unknown"), false);
});

test("두 stage fingerprint와 occurrence key가 golden 계약을 따른다", () => {
  for (const fixtureCase of fixture.fingerprintCases) {
    assert.equal(
      extractionIssueFingerprint(fixtureCase.input),
      fixtureCase.expectedFingerprint,
      fixtureCase.name
    );
  }
  for (const fixtureCase of fixture.occurrenceCases) {
    assert.equal(
      extractionIssueOccurrenceKey(fixtureCase.input),
      fixtureCase.expectedKey
    );
  }
});

test("runtime version은 종류가 같은 경우에만 비교한다", () => {
  assert.equal(
    encodeExtractionRuntimeVersion({kind: "contract", value: 2}),
    "contract:2"
  );
  assert.equal(
    encodeExtractionRuntimeVersion({kind: "extractor", value: "1.10.0"}),
    "extractor:1.10.0"
  );
  assert.equal(
    compareExtractionRuntimeVersions("contract:3", "contract:2"),
    1
  );
  assert.equal(
    compareExtractionRuntimeVersions(
      "extractor:1.10.0",
      "extractor:1.2.9"
    ),
    1
  );
  assert.equal(
    compareExtractionRuntimeVersions("contract:2", "extractor:2.0.0"),
    null
  );
  assert.equal(
    compareExtractionRuntimeVersions("extractor:1.0", "extractor:1.0.0"),
    null
  );
  assert.equal(
    extractionRuntimeVersionIsAtLeast("contract:2", "extractor:2.0.0"),
    false
  );
  assert.equal(
    encodeExtractionRuntimeVersionForStage({
      stage: "seasonDiscovery",
      value: 3,
    }),
    "contract:3"
  );
  assert.equal(
    encodeExtractionRuntimeVersionForStage({
      stage: "seasonImageImport",
      value: "2.1.0",
    }),
    "extractor:2.1.0"
  );
  assert.equal(
    extractionRuntimeVersionMatchesStage("seasonDiscovery", "contract:3"),
    true
  );
  assert.equal(
    extractionRuntimeVersionMatchesStage(
      "seasonImageImport",
      "contract:3"
    ),
    false
  );
});

test("fixed와 더 높은 같은 stage runtime만 앱 재시도를 허용한다", () => {
  assert.equal(isExtractionFixRetryEligible({
    issueStatus: "fixed",
    blockedRuntimeVersion: "contract:1",
    retryAvailableRuntimeVersion: "contract:2",
    stage: "seasonDiscovery",
  }), true);
  assert.equal(isExtractionFixRetryEligible({
    issueStatus: "inProgress",
    blockedRuntimeVersion: "extractor:1.2.0",
    retryAvailableRuntimeVersion: "extractor:1.3.0",
    stage: "seasonImageImport",
  }), false);
  assert.equal(isExtractionFixRetryEligible({
    issueStatus: "fixed",
    blockedRuntimeVersion: "extractor:1.3.0",
    retryAvailableRuntimeVersion: "extractor:1.3.0",
    stage: "seasonImageImport",
  }), false);
  assert.equal(isExtractionFixRetryEligible({
    issueStatus: "fixed",
    blockedRuntimeVersion: "contract:1",
    retryAvailableRuntimeVersion: "extractor:1.3.0",
    stage: "seasonDiscovery",
  }), false);
});

test("운영 action은 CAS와 허용 상태 전이를 강제한다", () => {
  const statuses: ExtractionIssueStatus[] = [
    "open",
    "inProgress",
    "needsGroundTruth",
    "fixed",
    "verified",
    "wontFix",
  ];
  const actions: ExtractionIssueAction[] = [
    "startProcessing",
    "markNeedsGroundTruth",
    "recordGroundTruthAndResume",
    "reopen",
    "markWontFix",
    "markFixed",
    "markVerified",
  ];
  const allowed = new Map<string, ExtractionIssueStatus>([
    ["open:startProcessing", "inProgress"],
    ["inProgress:markNeedsGroundTruth", "needsGroundTruth"],
    ["needsGroundTruth:recordGroundTruthAndResume", "inProgress"],
    ["needsGroundTruth:reopen", "open"],
    ["verified:reopen", "open"],
    ["wontFix:reopen", "open"],
    ["open:markWontFix", "wontFix"],
    ["inProgress:markWontFix", "wontFix"],
    ["needsGroundTruth:markWontFix", "wontFix"],
    ["inProgress:markFixed", "fixed"],
    ["fixed:markVerified", "verified"],
  ]);
  for (const status of statuses) {
    for (const action of actions) {
      const target = allowed.get(`${status}:${action}`);
      const transition = () => transitionExtractionIssueState({
        status,
        stateVersion: 4,
        expectedStateVersion: 4,
        action,
      });
      if (target === undefined) {
        assert.throws(transition, /허용되지 않은/);
      } else {
        assert.deepEqual(transition(), {status: target, stateVersion: 5});
      }
    }
  }
  assert.throws(() => transitionExtractionIssueState({
    status: "fixed",
    stateVersion: 6,
    expectedStateVersion: 5,
    action: "markVerified",
  }), /stateVersion/);
});

test("재발은 wontFix 또는 fixed runtime 이상에서만 reopen한다", () => {
  assert.deepEqual(resolveExtractionIssueOccurrence({
    status: "inProgress",
    stateVersion: 2,
    occurrenceRuntimeVersion: "extractor:2.0.0",
  }), {status: "inProgress", stateVersion: 2, isRecurrence: false});
  assert.deepEqual(resolveExtractionIssueOccurrence({
    status: "fixed",
    stateVersion: 3,
    occurrenceRuntimeVersion: "extractor:1.9.9",
    fixedRuntimeVersion: "extractor:2.0.0",
  }), {status: "fixed", stateVersion: 3, isRecurrence: false});
  assert.deepEqual(resolveExtractionIssueOccurrence({
    status: "verified",
    stateVersion: 7,
    occurrenceRuntimeVersion: "extractor:2.1.0",
    fixedRuntimeVersion: "extractor:2.0.0",
  }), {status: "open", stateVersion: 8, isRecurrence: true});
  assert.deepEqual(resolveExtractionIssueOccurrence({
    status: "wontFix",
    stateVersion: 9,
    occurrenceRuntimeVersion: "contract:1",
  }), {status: "open", stateVersion: 10, isRecurrence: true});
});

test("occurrence는 7일, terminal issue와 job은 60일 보존한다", () => {
  const now = new Date("2026-08-05T00:00:00.000Z");
  assert.equal(
    occurrenceEvidenceExpiresAt(now).toISOString(),
    "2026-08-12T00:00:00.000Z"
  );
  for (const status of [
    "open",
    "inProgress",
    "needsGroundTruth",
    "fixed",
  ] as const) {
    assert.equal(extractionIssueExpiresAt(status, now), null);
  }
  assert.equal(
    extractionIssueExpiresAt("verified", now)?.toISOString(),
    "2026-10-04T00:00:00.000Z"
  );
  assert.equal(
    extractionIssueExpiresAt("wontFix", now)?.toISOString(),
    "2026-10-04T00:00:00.000Z"
  );
  assert.equal(
    terminalExtractionJobExpiresAt(now).toISOString(),
    "2026-10-04T00:00:00.000Z"
  );
});
