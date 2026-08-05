import assert from "node:assert/strict";
import test from "node:test";
import {
  canRecordSeasonDiscoveryDispatch,
  canonicalDiscoveryURL,
  deterministicSeasonDiscoveryTaskID,
  isActionRequiredSeasonDiscoveryStatus,
  isActiveSeasonDiscoveryStatus,
  isSeasonAvailableForDiscoveryReview,
  isCurrentPublishedSeasonDiscoverySnapshot,
  isTerminalSeasonDiscoveryStatus,
  seasonDiscoveryExpiresAt,
  seasonDiscoveryRecommendedAction,
  seasonDiscoveryRequestFingerprint,
} from "./seasonDiscoveryContract.js";
import {
  seasonDiscoveryCreationFingerprint,
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
  }), "none");
});

test("discovery task ID는 dispatch generation을 포함한다", () => {
  const first = deterministicSeasonDiscoveryTaskID("brand", "job", 0);
  assert.match(first, /^season-discovery-/);
  assert.equal(first, deterministicSeasonDiscoveryTaskID("brand", "job", 0));
  assert.notEqual(first, deterministicSeasonDiscoveryTaskID("brand", "job", 1));
});

test("dispatch 기록은 같은 queued generation에만 적용한다", () => {
  const queued = {
    status: "queued",
    generation: 3,
    dispatchGeneration: 1,
    expectedGeneration: 3,
    expectedDispatchGeneration: 1,
  };
  assert.equal(canRecordSeasonDiscoveryDispatch(queued), true);
  for (const status of [
    "dispatching", "running", "succeeded", "awaitingReview", "failed",
  ]) {
    assert.equal(canRecordSeasonDiscoveryDispatch({...queued, status}), false);
  }
  assert.equal(canRecordSeasonDiscoveryDispatch({
    ...queued, generation: 4,
  }), false);
  assert.equal(canRecordSeasonDiscoveryDispatch({
    ...queued, dispatchGeneration: 2,
  }), false);
});

test("후보 import는 현재 공개된 snapshot 계약이 모두 일치해야 한다", () => {
  const current = {
    publishedJobID: "job-3",
    publishedGeneration: 3,
    publishedSnapshotHash: "snapshot-3",
    publishedExpiresAtMillis: 2_000,
    jobID: "job-3",
    jobGeneration: 3,
    jobSnapshotHash: "snapshot-3",
    jobStatus: "succeeded",
    candidateGeneration: 3,
    candidateSnapshotHash: "snapshot-3",
    candidateResolution: "newSeason",
    expectedGeneration: 3,
    expectedSnapshotHash: "snapshot-3",
    nowMillis: 1_000,
  };
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot(current), true);
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot({
    ...current,
    publishedJobID: null,
    publishedGeneration: null,
    publishedSnapshotHash: null,
  }), false);
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot({
    ...current, publishedGeneration: 4,
  }), false);
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot({
    ...current, candidateSnapshotHash: "stale-snapshot",
  }), false);
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot({
    ...current, publishedExpiresAtMillis: 1_000,
  }), false);
  assert.equal(isCurrentPublishedSeasonDiscoverySnapshot({
    ...current, jobStatus: "running",
  }), false);
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
