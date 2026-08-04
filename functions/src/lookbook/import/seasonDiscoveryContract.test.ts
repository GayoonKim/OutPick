import assert from "node:assert/strict";
import test from "node:test";
import {
  canonicalDiscoveryURL,
  deterministicSeasonDiscoveryTaskID,
  isActionRequiredSeasonDiscoveryStatus,
  isActiveSeasonDiscoveryStatus,
  isSeasonAvailableForDiscoveryReview,
  isTerminalSeasonDiscoveryStatus,
  seasonDiscoveryExpiresAt,
  seasonDiscoveryBlockedRevision,
  normalizedSeasonDiscoveryIssueFingerprint,
  seasonDiscoveryImprovementDisposition,
  seasonDiscoveryRecommendedAction,
  seasonDiscoveryRequestFingerprint,
} from "./seasonDiscoveryContract.js";
import {
  seasonDiscoveryCreationFingerprint,
  SEASON_DISCOVERY_CONTRACT_REVISION,
  SEASON_DISCOVERY_EXTRACTOR_VERSION,
  SEASON_DISCOVERY_LIMITS,
  SEASON_DISCOVERY_SCHEMA_VERSION,
} from "../../shared/seasonDiscoveryCreation.js";

const baseInput = {
  brandID: "brand-1",
  sourceArchiveURL: "https://EXAMPLE.com:443/archive?utm_source=x&b=2&a=1#top",
  extractorVersion: "v1",
  extractionContractRevision: 1,
  adapterKey: null,
  adapterVersion: null,
  schemaVersion: 1,
  limits: {maxStoredCandidates: 80, maxLoadMoreClicks: 20},
};

test("discovery fingerprint는 URL과 limits 순서를 정규화한다", () => {
  const first = seasonDiscoveryRequestFingerprint(baseInput);
  const second = seasonDiscoveryRequestFingerprint({
    ...baseInput,
    sourceArchiveURL: "https://example.com/archive?a=1&b=2",
    limits: {maxLoadMoreClicks: 20, maxStoredCandidates: 80},
  });
  assert.equal(first, second);
  assert.equal(
    seasonDiscoveryRequestFingerprint({
      ...baseInput,
      extractorVersion: SEASON_DISCOVERY_EXTRACTOR_VERSION,
      schemaVersion: SEASON_DISCOVERY_SCHEMA_VERSION,
      limits: SEASON_DISCOVERY_LIMITS,
    }),
    seasonDiscoveryCreationFingerprint(
      baseInput.brandID, baseInput.sourceArchiveURL
    )
  );
  assert.notEqual(first, seasonDiscoveryRequestFingerprint({
    ...baseInput,
    extractorVersion: "v2",
  }));
  assert.notEqual(first, seasonDiscoveryRequestFingerprint({
    ...baseInput,
    extractionContractRevision: 2,
  }));
  assert.equal(
    canonicalDiscoveryURL(baseInput.sourceArchiveURL),
    "https://example.com/archive?a=1&b=2"
  );
});

test("개선 요청은 같은 revision 재시도 없이 준비 상태로 전이한다", () => {
  const legacyFingerprint = "a".repeat(64);
  assert.equal(
    normalizedSeasonDiscoveryIssueFingerprint(legacyFingerprint),
    "a".repeat(40)
  );
  assert.equal(normalizedSeasonDiscoveryIssueFingerprint("a".repeat(39)), null);
  assert.equal(seasonDiscoveryBlockedRevision({
    blockedRevision: undefined,
    extractionContractRevision: undefined,
    currentRevision: 1,
  }), 1);
  assert.equal(seasonDiscoveryBlockedRevision({
    blockedRevision: undefined,
    extractionContractRevision: 2,
    currentRevision: 3,
  }), 2);
  assert.equal(seasonDiscoveryImprovementDisposition({
    status: "correctionRequired",
    improvementRequested: false,
    blockedRevision: SEASON_DISCOVERY_CONTRACT_REVISION,
    availableRevision: null,
  }), "requestable");
  assert.equal(seasonDiscoveryImprovementDisposition({
    status: "correctionRequired",
    improvementRequested: true,
    blockedRevision: 1,
    availableRevision: 1,
  }), "requested");
  assert.equal(seasonDiscoveryImprovementDisposition({
    status: "correctionRequired",
    improvementRequested: true,
    blockedRevision: 1,
    availableRevision: 2,
  }), "ready");
  assert.equal(seasonDiscoveryImprovementDisposition({
    status: "correctionRequired",
    improvementRequested: true,
    blockedRevision: 1,
    availableRevision: 2,
    resolvedByJobID: "job-2",
  }), "notEligible");
});

test("상태 그룹과 lifecycle retention이 계약대로 분리된다", () => {
  assert.equal(isActiveSeasonDiscoveryStatus("running"), true);
  assert.equal(isActionRequiredSeasonDiscoveryStatus("awaitingReview"), true);
  assert.equal(isTerminalSeasonDiscoveryStatus("superseded"), true);
  const now = new Date("2026-08-04T00:00:00.000Z");
  assert.equal(seasonDiscoveryExpiresAt("running", now), null);
  assert.equal(seasonDiscoveryExpiresAt("correctionRequired", now), null);
  assert.equal(
    seasonDiscoveryExpiresAt("succeeded", now)?.toISOString(),
    "2026-09-03T00:00:00.000Z"
  );
  assert.equal(
    seasonDiscoveryExpiresAt("failed", now)?.toISOString(),
    "2026-10-03T00:00:00.000Z"
  );
});

test("실패와 검토 상태는 관리자 action으로 결정적으로 변환된다", () => {
  assert.equal(seasonDiscoveryRecommendedAction({
    status: "failed", retryable: true,
  }), "retry");
  assert.equal(seasonDiscoveryRecommendedAction({
    status: "failed", errorCode: "source_not_found",
  }), "updateSourceURL");
  assert.equal(seasonDiscoveryRecommendedAction({
    status: "awaitingReview",
  }), "reviewCandidates");
  assert.equal(seasonDiscoveryRecommendedAction({
    status: "correctionRequired",
  }), "waitForExtractorFix");
});

test("discovery task ID는 dispatch generation을 포함한다", () => {
  const first = deterministicSeasonDiscoveryTaskID("brand", "job", 0);
  assert.match(first, /^season-discovery-/);
  assert.equal(first, deterministicSeasonDiscoveryTaskID("brand", "job", 0));
  assert.notEqual(first, deterministicSeasonDiscoveryTaskID("brand", "job", 1));
});

test("관리자 검토 연결은 삭제되지 않은 기존 시즌만 허용한다", () => {
  assert.equal(isSeasonAvailableForDiscoveryReview(undefined), false);
  assert.equal(isSeasonAvailableForDiscoveryReview({}), true);
  assert.equal(
    isSeasonAvailableForDiscoveryReview({deletionStatus: "active"}),
    true
  );
  assert.equal(
    isSeasonAvailableForDiscoveryReview({deletionStatus: "deleteRequested"}),
    false
  );
  assert.equal(
    isSeasonAvailableForDiscoveryReview({deletionStatus: "deleted"}),
    false
  );
});
