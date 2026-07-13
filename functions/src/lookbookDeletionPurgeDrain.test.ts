import assert from "node:assert/strict";
import test from "node:test";

import {
  comparePurgeDrainCandidates,
  drainPurgeCandidatePages,
  type PurgeDrainCandidate,
} from "./lookbookDeletionPurgeDrain.js";

interface TestCandidate extends PurgeDrainCandidate {
  sequence: number;
}

/**
 * 테스트 요청 fixture를 만든다.
 * @param {number} sequence 테스트 순번
 * @param {string} brandID 브랜드 ID
 * @param {PurgeDrainTargetType} targetType 삭제 target type
 * @param {number} purgeAfterMillis 삭제 예정 시각
 * @return {TestCandidate} 테스트 요청
 */
function candidate(
  sequence: number,
  brandID: string,
  targetType: PurgeDrainCandidate["targetType"] = "post",
  purgeAfterMillis: number = sequence
): TestCandidate {
  return {
    sequence,
    requestID: `request-${sequence.toString().padStart(3, "0")}`,
    brandID,
    targetType,
    purgeAfterMillis,
  };
}

test("20개를 넘는 page를 끝까지 반복 처리한다", async () => {
  const pages = [
    Array.from({length: 20}, (_, index) => candidate(index, `brand-${index}`)),
    Array.from(
      {length: 5},
      (_, index) => candidate(index + 20, `brand-${index + 20}`)
    ),
  ];
  let pageIndex = 0;
  const executed: number[] = [];

  const summary = await drainPurgeCandidatePages({
    loadPage: async () => ({
      candidates: pages[pageIndex],
      hasMore: pageIndex++ < pages.length - 1,
    }),
    execute: async (item) => {
      executed.push(item.sequence);
      return "succeeded";
    },
    canStartNewWork: () => true,
    maxConcurrentBrands: 3,
  });

  assert.equal(executed.length, 25);
  assert.equal(summary.pageCount, 2);
  assert.equal(summary.successCount, 25);
  assert.equal(summary.hasRemainingCandidates, false);
});

test("서로 다른 브랜드는 최대 3개만 동시에 실행한다", async () => {
  const items = Array.from(
    {length: 8},
    (_, index) => candidate(index, `brand-${index}`)
  );
  let activeCount = 0;
  let maxActiveCount = 0;

  const summary = await drainPurgeCandidatePages({
    loadPage: async () => ({candidates: items, hasMore: false}),
    execute: async () => {
      activeCount += 1;
      maxActiveCount = Math.max(maxActiveCount, activeCount);
      await new Promise((resolve) => setTimeout(resolve, 5));
      activeCount -= 1;
      return "succeeded";
    },
    canStartNewWork: () => true,
    maxConcurrentBrands: 3,
  });

  assert.equal(maxActiveCount, 3);
  assert.equal(summary.successCount, items.length);
});

test("같은 브랜드는 순차 실행하고 부모 target을 먼저 처리한다", async () => {
  const items = [
    candidate(1, "brand-a", "post", 10),
    candidate(2, "brand-a", "brand", 30),
    candidate(3, "brand-a", "season", 20),
  ];
  const order: string[] = [];
  let activeCount = 0;
  let maxActiveCount = 0;

  await drainPurgeCandidatePages({
    loadPage: async () => ({candidates: items, hasMore: false}),
    execute: async (item) => {
      activeCount += 1;
      maxActiveCount = Math.max(maxActiveCount, activeCount);
      order.push(item.targetType);
      await Promise.resolve();
      activeCount -= 1;
      return "succeeded";
    },
    canStartNewWork: () => true,
    maxConcurrentBrands: 3,
  });

  assert.deepEqual(order, ["brand", "season", "post"]);
  assert.equal(maxActiveCount, 1);
});

test("같은 target type은 purgeAfter와 requestID 순으로 정렬한다", () => {
  const items = [
    candidate(2, "brand-a", "post", 20),
    candidate(3, "brand-a", "post", 10),
    candidate(1, "brand-a", "post", 20),
  ].sort(comparePurgeDrainCandidates);

  assert.deepEqual(items.map((item) => item.sequence), [3, 1, 2]);
});

test("개별 실패와 lease skip 이후에도 나머지를 처리한다", async () => {
  const items = [
    candidate(1, "brand-a"),
    candidate(2, "brand-b"),
    candidate(3, "brand-c"),
  ];

  const summary = await drainPurgeCandidatePages({
    loadPage: async () => ({candidates: items, hasMore: false}),
    execute: async (item) => {
      if (item.sequence === 1) return "failed";
      if (item.sequence === 2) return "skipped";
      return "succeeded";
    },
    canStartNewWork: () => true,
    maxConcurrentBrands: 3,
  });

  assert.equal(summary.failureCount, 1);
  assert.equal(summary.skippedCount, 1);
  assert.equal(summary.successCount, 1);
  assert.equal(summary.startedCount, 2);
  assert.equal(summary.hasRemainingCandidates, true);
});

test("시간 예산 이후 신규 작업을 시작하지 않는다", async () => {
  const items = [
    candidate(1, "brand-a"),
    candidate(2, "brand-a"),
    candidate(3, "brand-a"),
  ];
  let now = 0;
  const started: number[] = [];

  const summary = await drainPurgeCandidatePages({
    loadPage: async () => ({candidates: items, hasMore: true}),
    execute: async (item) => {
      started.push(item.sequence);
      now += 6;
      return "succeeded";
    },
    canStartNewWork: () => now < 10,
    maxConcurrentBrands: 3,
  });

  assert.deepEqual(started, [1, 2]);
  assert.equal(summary.successCount, 2);
  assert.equal(summary.unstartedCount, 1);
  assert.equal(summary.stopReason, "time_budget");
  assert.equal(summary.hasRemainingCandidates, true);
});
