import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";

const fixtureURL = new URL("../fixtures/performance-remote-input-amd64.json", import.meta.url);
const expectedDigest = "c4fb65f71fa5f26a6f9a531e58b8629ba2aff0f612c81e75e7cdeb05028f0c56";
const seasonOrder = ["2026FW", "2026SS", "2025FW", "2025SS", "2024FW", "2024SS"];
export const fixture = JSON.parse(readFileSync(fixtureURL, "utf8"));
assert.equal(fixture.sourceInputDigest, expectedDigest);
assert.deepEqual(fixture.seasons.map((season) => season.seasonID), seasonOrder);

export function uniqueImages(season) {
  const seen = new Set();
  return season.images.filter((image) => {
    if (seen.has(image.sha256)) return false;
    seen.add(image.sha256);
    return true;
  });
}

export function makePlan(stage) {
  assert.ok(["smoke", "tenBrands"].includes(stage), "승인되지 않은 실행 단계");
  // 기존 순환 배정에서 A의 반복 2자리만 제거한다. B~J의 원본은 유지한다.
  const selections = stage === "smoke" ? [
    ["A", ["2026SS", "2025FW"]], ["B", ["2025SS"]],
  ] : [
    ["A", seasonOrder], ["B", ["2025FW", "2025SS"]],
    ..."CDEFGHIJ".split("").map((brand, index) =>
      [brand, [seasonOrder[(index + 10) % 6]]]),
  ];
  const brands = selections.map(([brand, seasons], index) => ({
    brand, seasons,
    discoveryOffsetMs: stage === "tenBrands" ? index * 100 : null,
    importOffsetMs: stage === "tenBrands" ? index * 100 : null,
  }));
  const totals = {seasons: 0, extractionImageGets: 0, extractionImageBytes: 0,
    approvedStorageImageGets: 0, approvedStorageImageBytes: 0,
    jpegWrites: 0, jpegBytes: 0, assets: 0};
  for (const brand of brands) {
    assert.equal(new Set(brand.seasons).size, brand.seasons.length);
    for (const id of brand.seasons) {
      const season = fixture.seasons.find((item) => item.seasonID === id);
      const cover = fixture.covers.find((item) => item.seasonID === id);
      const golden = fixture.golden.find((item) => item.seasonID === id);
      assert.ok(season && cover && golden, `fixture 누락: ${id}`);
      const images = uniqueImages(season);
      assert.equal(images.length, golden.uniqueImages);
      assert.equal(golden.outputs.length, golden.uploadFiles);
      assert.equal(golden.outputs.reduce((sum, item) => sum + item.bytes, 0), golden.uploadBytes);
      totals.seasons++;
      totals.extractionImageGets += season.images.length + 1;
      totals.extractionImageBytes += season.images.reduce((sum, image) => sum + image.bytes, cover.bytes);
      totals.approvedStorageImageGets += images.length + 1;
      totals.approvedStorageImageBytes += images.reduce((sum, image) => sum + image.bytes, cover.bytes);
      totals.jpegWrites += golden.uploadFiles;
      totals.jpegBytes += golden.uploadBytes;
      totals.assets += golden.assetTargets;
    }
  }
  const plan = {version: 1, stage, projectID: "outpick-test", region: "asia-northeast3",
    archiveURL: "https://unaffected.co.kr/collection.html?cate_no=88",
    sourceInputDigest: expectedDigest,
    fixtureSha256: createHash("sha256").update(readFileSync(fixtureURL)).digest("hex"),
    brands, policy: {seasonConcurrency: 6, download: 4, transform: 1, upload: 4,
      sourceReuseBytes: 128 * 1024 * 1024},
    totals: {...totals, verificationGets: totals.jpegWrites,
      verificationMetadataGets: totals.jpegWrites,
      verificationBytes: totals.jpegBytes,
      mutationRequestsIfAllReviewed: brands.length * 2 + totals.seasons},
    accounting: "재시도 없는 추출 해시 1회 + 별도 승인 실행의 고유 원본/커버 1회. HTML, 브라우저, SDK, 캐시 miss/재시도, 상태 조회는 별도이며 청구 상한이 아님",
  };
  return {...plan, planDigest: createHash("sha256").update(JSON.stringify(plan)).digest("hex")};
}

// 정상 검토 API를 호출하기 직전에 서버 응답과 저장된 job 원본을 함께 대조한다.
export function assertReviewMatches(seasonID, review, job) {
  const season = fixture.seasons.find((item) => item.seasonID === seasonID);
  const cover = fixture.covers.find((item) => item.seasonID === seasonID);
  assert.ok(season && cover, "알 수 없는 시즌");
  assert.equal(job.sourceURL, season.sourceURL);
  assert.equal(job.coverRemoteURL, cover.sourceURL);
  assert.equal(job.status, "awaitingReview");
  assert.equal(review.status, "awaitingReview");
  assert.equal(review.brandID, job.brandID);
  assert.equal(review.jobID, job.jobID);
  assert.equal(review.reviewGeneration, job.reviewGeneration);
  assert.ok(Number.isSafeInteger(review.reviewGeneration) && review.reviewGeneration >= 0);
  assert.ok(typeof review.reviewSnapshotHash === "string" && review.reviewSnapshotHash.length > 0);
  assert.equal(review.reviewSnapshotHash, job.reviewSnapshotHash);
  assert.equal(job.contentHashResolutionComplete, true);
  const expected = uniqueImages(season);
  assert.deepEqual(review.candidates.map((item) => item.sourceURL), expected.map((item) => item.sourceURL));
  assert.deepEqual(job.imageCandidates.map((item) => item.sourceURL), expected.map((item) => item.sourceURL));
  const keys = review.candidates.map((item) => item.candidateKey);
  assert.ok(keys.every((key) => typeof key === "string" && key.length > 0));
  assert.equal(new Set(keys).size, keys.length);
  assert.deepEqual(keys, job.reviewCandidateKeys);
  const hashes = new Map(job.imageCandidateContentHashes.map((item) => [item.candidateKey, item.contentHash]));
  expected.forEach((image, index) => assert.equal(hashes.get(keys[index]), image.sha256));
  return {reviewGeneration: review.reviewGeneration, reviewSnapshotHash: review.reviewSnapshotHash,
    decision: "approved", excludedCandidateKeys: [], expectedCandidateCount: expected.length};
}

// Firestore의 시각/sequence 원본을 사용하며 클라이언트 발송 순서로 성공을 추정하지 않는다.
export function assertBatchRunEvidence(batches, expectedBatchIDs, revision) {
  assert.ok(typeof revision === "string" && revision.startsWith("lookbook-import-worker-development-"));
  assert.ok(expectedBatchIDs.length > 0);
  assert.equal(new Set(expectedBatchIDs).size, expectedBatchIDs.length);
  assert.deepEqual(batches.map((batch) => batch.id).sort(), [...expectedBatchIDs].sort());
  const ordered = [...batches].sort((a, b) => a.sequence - b.sequence);
  let previousRelease = 0;
  const sequences = new Set();
  for (const batch of ordered) {
    assert.ok(Number.isSafeInteger(batch.sequence) && batch.sequence >= 1);
    assert.ok(!sequences.has(batch.sequence)); sequences.add(batch.sequence);
    assert.equal(batch.state, "released");
    assert.ok(Number.isSafeInteger(batch.releasedAt) && batch.releasedAt > 0);
    assert.ok(batch.runs.length > 0, "실행 증거 없는 요청");
    const runs = [...batch.runs].sort((a, b) => a.startedAt - b.startedAt);
    assert.equal(new Set(runs.map((run) => run.runID)).size, runs.length);
    let finishedAt = previousRelease;
    for (const run of runs) {
      assert.equal(run.batchID, batch.id);
      assert.equal(run.projectID, "outpick-test");
      assert.equal(run.revision, revision);
      assert.ok(Number.isSafeInteger(run.epoch) && run.epoch > 0);
      assert.ok(typeof run.bootID === "string" && run.bootID.length > 0);
      assert.equal(run.runID, `${batch.id}-${run.epoch}`);
      assert.equal(run.terminalConfirmed, true);
      assert.equal(run.inFlight, 0);
      assert.ok(Number.isSafeInteger(run.startedAt) && run.startedAt >= finishedAt,
        "이전 작업 정리 전에 실행 시작");
      assert.ok(Number.isSafeInteger(run.finishedAt) && run.finishedAt >= run.startedAt);
      assert.ok(["queued", "released"].includes(run.state));
      const memory = run.resourceEvidence;
      assert.ok(memory && memory.sampleCount > 0);
      assert.equal(memory.memoryLimitBytes, 2 * 1024 ** 3);
      assert.ok(["cgroup-v1", "cgroup-v2"].includes(memory.memorySource));
      assert.ok(Number.isFinite(memory.maxMemoryRatio) && memory.maxMemoryRatio >= 0 && memory.maxMemoryRatio <= 1);
      assert.equal(memory.memoryStop, null);
      assert.equal(memory.drainTargetExceeded, false);
      finishedAt = run.finishedAt;
    }
    assert.equal(runs.at(-1).state, "released");
    assert.equal(batch.runID, runs.at(-1).runID);
    assert.equal(batch.epoch, runs.at(-1).epoch);
    assert.ok(batch.releasedAt >= finishedAt);
    previousRelease = batch.releasedAt;
  }
  return {batches: ordered.length, runs: ordered.reduce((sum, batch) => sum + batch.runs.length, 0)};
}
