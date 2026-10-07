import assert from "node:assert/strict";
import {test} from "node:test";
import {makePlan, fixture, uniqueImages, assertReviewMatches,
  assertBatchRunEvidence} from "./queue-development-contract.mjs";

test("QD01 승인된 16시즌과 100ms 접수 및 3시즌 smoke를 분리한다", () => {
  const plan = makePlan("tenBrands");
  assert.deepEqual(plan.brands.map((brand) => brand.seasons.length), [6, 2, 1, 1, 1, 1, 1, 1, 1, 1]);
  const arrivals = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900];
  assert.deepEqual(plan.brands.map((brand) => brand.discoveryOffsetMs), arrivals);
  assert.deepEqual(plan.brands.map((brand) => brand.importOffsetMs), arrivals);
  assert.equal(plan.totals.seasons, 16);
  assert.equal(plan.totals.mutationRequestsIfAllReviewed, 36);
  assert.equal(makePlan("smoke").totals.mutationRequestsIfAllReviewed, 7);
  assert.throws(() => makePlan("repeat"));
  assert.equal(makePlan("tenBrands").planDigest, plan.planDigest);
});

test("QD02 검토 후 재다운로드와 중복 해시 제거를 전송량에 반영한다", () => {
  const totals = makePlan("smoke").totals;
  assert.equal(totals.extractionImageGets, 64);
  assert.equal(totals.approvedStorageImageGets, 63);
  assert.equal(totals.extractionImageBytes, 28241613);
  assert.equal(totals.jpegWrites, 126);
  assert.equal(totals.jpegBytes, 15614243);
  assert.equal(totals.verificationGets, 126);
  assert.equal(totals.assets, 63);
  const input = fixture.seasons.find((season) => season.seasonID === "2025SS");
  assert.equal(input.images.length, 17);
  assert.equal(uniqueImages(input).length, 16);
  assert.ok(totals.approvedStorageImageBytes < 28241613);
});

function reviewFixture() {
  const season = fixture.seasons.find((item) => item.seasonID === "2025SS");
  const images = uniqueImages(season);
  const keys = images.map((_, index) => `candidate-${index}`);
  const job = {brandID: "qa-brand", jobID: "qa-job", status: "awaitingReview",
    sourceURL: season.sourceURL,
    coverRemoteURL: fixture.covers.find((item) => item.seasonID === season.seasonID).sourceURL,
    reviewGeneration: 1, reviewSnapshotHash: "snapshot", contentHashResolutionComplete: true,
    imageCandidates: images.map((image) => ({sourceURL: image.sourceURL})),
    reviewCandidateKeys: keys,
    imageCandidateContentHashes: images.map((image, index) =>
      ({candidateKey: keys[index], contentHash: image.sha256}))};
  const review = {brandID: job.brandID, jobID: job.jobID, status: job.status,
    reviewGeneration: 1, reviewSnapshotHash: "snapshot",
    candidates: images.map((image, index) => ({sourceURL: image.sourceURL, candidateKey: keys[index]}))};
  return {review, job};
}

test("QD03 고정 원본과 일치한 검토만 정상 승인 payload를 만든다", () => {
  const {review, job} = reviewFixture();
  assert.deepEqual(assertReviewMatches("2025SS", review, job), {
    reviewGeneration: 1, reviewSnapshotHash: "snapshot", decision: "approved",
    excludedCandidateKeys: [], expectedCandidateCount: 16,
  });
});

test("QD04 후보 순서 해시 커버 및 검토 세대 변경은 승인을 차단한다", () => {
  const changes = [
    ({review}) => review.candidates.reverse(),
    ({review}) => review.candidates.pop(),
    ({job}) => {job.coverRemoteURL = "https://example.com/changed.jpg";},
    ({job}) => {job.imageCandidateContentHashes[0].contentHash = "changed";},
    ({review}) => {review.reviewGeneration++;},
    ({job}) => {job.contentHashResolutionComplete = false;},
    ({review}) => {review.candidates[1].candidateKey = review.candidates[0].candidateKey;},
    ({job}) => {job.status = "succeeded";},
    ({review}) => {review.brandID = "another";},
  ];
  for (const change of changes) {
    const value = reviewFixture(); change(value);
    assert.throws(() => assertReviewMatches("2025SS", value.review, value.job));
  }
});

const revision = "lookbook-import-worker-development-qa";
function batchesFixture() {
  return ["b", "a"].map((id, index) => ({id, sequence: index + 1,
    state: "released", releasedAt: 200 + index * 200,
    runID: `${id}-${index + 1}`, epoch: index + 1,
    runs: [{batchID: id, projectID: "outpick-test", revision,
      epoch: index + 1, bootID: "boot", runID: `${id}-${index + 1}`,
      startedAt: 100 + index * 200, finishedAt: 200 + index * 200,
      terminalConfirmed: true, inFlight: 0, state: "released",
      resourceEvidence: {sampleCount: 10, memoryLimitBytes: 2 * 1024 ** 3,
        memorySource: "cgroup-v2", maxMemoryRatio: 0.5,
        memoryStop: null, drainTargetExceeded: false}}]}));
}

test("QD05 서버 순번과 정리 증거를 기준으로 FIFO를 판정한다", () => {
  assert.deepEqual(assertBatchRunEvidence(batchesFixture().reverse(), ["a", "b"], revision), {batches: 2, runs: 2});
});

test("QD06 누락 중첩 종료불명확 메모리 중단과 다른 revision은 통과하지 않는다", () => {
  const changes = [
    (batches) => batches.pop(),
    (batches) => {batches[1].runs[0].startedAt = 199;},
    (batches) => {batches[0].runs[0].terminalConfirmed = false;},
    (batches) => {batches[0].runs[0].inFlight = 1;},
    (batches) => {batches[0].runs[0].revision = "old";},
    (batches) => {batches[0].runs[0].resourceEvidence.memoryStop = "MEMORY_HIGH";},
    (batches) => {batches[0].runs[0].resourceEvidence = null;},
    (batches) => {batches[0].runs = [];},
    (batches) => {batches[1].sequence = 1;},
    (batches) => {batches[0].state = "recoveryRequired";},
    (batches) => {batches[0].runID = "missing-final-run";},
    (batches) => {batches[0].epoch++;},
  ];
  for (const change of changes) {
    const batches = batchesFixture(); change(batches);
    assert.throws(() => assertBatchRunEvidence(batches, ["a", "b"], revision));
  }
  assert.throws(() => assertBatchRunEvidence([], [], revision));
});
