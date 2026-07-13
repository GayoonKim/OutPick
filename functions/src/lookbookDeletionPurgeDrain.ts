export type PurgeDrainTargetType = "brand" | "season" | "post";

export type PurgeDrainExecutionOutcome =
  "succeeded" |
  "failed" |
  "skipped";

export interface PurgeDrainCandidate {
  requestID: string;
  brandID: string | null;
  targetType: PurgeDrainTargetType;
  purgeAfterMillis: number;
}

export interface PurgeDrainPage<T extends PurgeDrainCandidate> {
  candidates: T[];
  hasMore: boolean;
}

export interface PurgeDrainSummary {
  pageCount: number;
  loadedCount: number;
  startedCount: number;
  successCount: number;
  failureCount: number;
  skippedCount: number;
  unstartedCount: number;
  stopReason: "drained" | "time_budget";
  hasRemainingCandidates: boolean;
}

interface PurgeDrainBatchSummary {
  startedCount: number;
  successCount: number;
  failureCount: number;
  skippedCount: number;
  unstartedCount: number;
}

const TARGET_PRIORITY: Record<PurgeDrainTargetType, number> = {
  brand: 0,
  season: 1,
  post: 2,
};

/**
 * 같은 브랜드 queue 안에서 부모 target과 오래된 요청을 먼저 정렬한다.
 * @param {PurgeDrainCandidate} lhs 왼쪽 요청
 * @param {PurgeDrainCandidate} rhs 오른쪽 요청
 * @return {number} 정렬 비교 결과
 */
export function comparePurgeDrainCandidates(
  lhs: PurgeDrainCandidate,
  rhs: PurgeDrainCandidate
): number {
  const targetOrder =
    TARGET_PRIORITY[lhs.targetType] - TARGET_PRIORITY[rhs.targetType];
  if (targetOrder !== 0) {
    return targetOrder;
  }
  if (lhs.purgeAfterMillis !== rhs.purgeAfterMillis) {
    return lhs.purgeAfterMillis - rhs.purgeAfterMillis;
  }
  return lhs.requestID.localeCompare(rhs.requestID);
}

/**
 * 빈 page batch 요약을 만든다.
 * @return {PurgeDrainBatchSummary} 빈 batch 요약
 */
function emptyBatchSummary(): PurgeDrainBatchSummary {
  return {
    startedCount: 0,
    successCount: 0,
    failureCount: 0,
    skippedCount: 0,
    unstartedCount: 0,
  };
}

/**
 * 빈 전체 drain 요약을 만든다.
 * @return {PurgeDrainSummary} 빈 drain 요약
 */
function emptyDrainSummary(): PurgeDrainSummary {
  return {
    pageCount: 0,
    loadedCount: 0,
    startedCount: 0,
    successCount: 0,
    failureCount: 0,
    skippedCount: 0,
    unstartedCount: 0,
    stopReason: "drained",
    hasRemainingCandidates: false,
  };
}

/**
 * 요청을 같은 브랜드 queue로 묶는 key를 만든다.
 * @param {PurgeDrainCandidate} candidate purge 요청
 * @return {string} 브랜드 queue key
 */
function brandQueueKey(candidate: PurgeDrainCandidate): string {
  return candidate.brandID ?? `request:${candidate.requestID}`;
}

/**
 * page 요청을 브랜드별 순차 queue로 묶는다.
 * @param {Array<PurgeDrainCandidate>} candidates page 요청
 * @return {Array<Array<PurgeDrainCandidate>>} 브랜드별 순차 queue
 */
function groupCandidatesByBrand<T extends PurgeDrainCandidate>(
  candidates: T[]
): T[][] {
  const queuesByBrand = new Map<string, T[]>();
  for (const candidate of candidates) {
    const key = brandQueueKey(candidate);
    const queue = queuesByBrand.get(key) ?? [];
    queue.push(candidate);
    queuesByBrand.set(key, queue);
  }

  return Array.from(queuesByBrand.entries())
    .map(([key, queue]) => ({
      key,
      queue: queue.sort(comparePurgeDrainCandidates),
    }))
    .sort((lhs, rhs) => {
      const candidateOrder = comparePurgeDrainCandidates(
        lhs.queue[0],
        rhs.queue[0]
      );
      return candidateOrder !== 0 ?
        candidateOrder :
        lhs.key.localeCompare(rhs.key);
    })
    .map((entry) => entry.queue);
}

/**
 * 한 page를 bounded brand worker로 처리한다.
 * @param {PurgeDrainCandidate[]} candidates page 요청
 * @param {number} maxConcurrentBrands 동시 브랜드 상한
 * @param {function} canStartNewWork 신규 작업 시작 가능 여부
 * @param {function} execute 요청 실행 함수
 * @return {Promise<PurgeDrainBatchSummary>} batch 실행 요약
 */
async function drainCandidateBatch<T extends PurgeDrainCandidate>(
  candidates: T[],
  maxConcurrentBrands: number,
  canStartNewWork: () => boolean,
  execute: (candidate: T) => Promise<PurgeDrainExecutionOutcome>
): Promise<PurgeDrainBatchSummary> {
  const summary = emptyBatchSummary();
  const brandQueues = groupCandidatesByBrand(candidates);
  let nextQueueIndex = 0;

  const worker = async (): Promise<void> => {
    while (nextQueueIndex < brandQueues.length) {
      const queueIndex = nextQueueIndex;
      nextQueueIndex += 1;
      const queue = brandQueues[queueIndex];

      for (const candidate of queue) {
        if (!canStartNewWork()) {
          return;
        }

        const outcome = await execute(candidate);
        switch (outcome) {
        case "succeeded":
          summary.startedCount += 1;
          summary.successCount += 1;
          break;
        case "failed":
          summary.startedCount += 1;
          summary.failureCount += 1;
          break;
        case "skipped":
          summary.skippedCount += 1;
          break;
        }
      }
    }
  };

  const workerCount = Math.min(
    Math.max(1, maxConcurrentBrands),
    brandQueues.length
  );
  await Promise.all(Array.from({length: workerCount}, () => worker()));

  const completedCount =
    summary.successCount + summary.failureCount + summary.skippedCount;
  summary.unstartedCount = candidates.length - completedCount;
  return summary;
}

/**
 * page loader와 purge worker를 분리해 시간 예산 안에서 queue를 반복 소진한다.
 * @param {object} options drain 실행 의존성
 * @return {Promise<PurgeDrainSummary>} 전체 drain 요약
 */
export async function drainPurgeCandidatePages<
  T extends PurgeDrainCandidate,
>(options: {
  loadPage: () => Promise<PurgeDrainPage<T>>;
  execute: (candidate: T) => Promise<PurgeDrainExecutionOutcome>;
  canStartNewWork: () => boolean;
  maxConcurrentBrands: number;
}): Promise<PurgeDrainSummary> {
  const summary = emptyDrainSummary();

  while (options.canStartNewWork()) {
    const page = await options.loadPage();
    summary.pageCount += 1;
    summary.loadedCount += page.candidates.length;

    const batchSummary = await drainCandidateBatch(
      page.candidates,
      options.maxConcurrentBrands,
      options.canStartNewWork,
      options.execute
    );
    summary.startedCount += batchSummary.startedCount;
    summary.successCount += batchSummary.successCount;
    summary.failureCount += batchSummary.failureCount;
    summary.skippedCount += batchSummary.skippedCount;
    summary.unstartedCount += batchSummary.unstartedCount;

    if (batchSummary.unstartedCount > 0) {
      summary.stopReason = "time_budget";
      summary.hasRemainingCandidates = true;
      return summary;
    }
    if (!page.hasMore) {
      summary.hasRemainingCandidates = summary.skippedCount > 0;
      return summary;
    }
  }

  summary.stopReason = "time_budget";
  summary.hasRemainingCandidates = true;
  return summary;
}

/**
 * 여러 target pass의 실행 결과를 scheduler 요약으로 합친다.
 * @param {PurgeDrainSummary} lhs 누적 요약
 * @param {PurgeDrainSummary} rhs 새 target pass 요약
 * @return {PurgeDrainSummary} 병합된 요약
 */
export function mergePurgeDrainSummaries(
  lhs: PurgeDrainSummary,
  rhs: PurgeDrainSummary
): PurgeDrainSummary {
  return {
    pageCount: lhs.pageCount + rhs.pageCount,
    loadedCount: lhs.loadedCount + rhs.loadedCount,
    startedCount: lhs.startedCount + rhs.startedCount,
    successCount: lhs.successCount + rhs.successCount,
    failureCount: lhs.failureCount + rhs.failureCount,
    skippedCount: lhs.skippedCount + rhs.skippedCount,
    unstartedCount: lhs.unstartedCount + rhs.unstartedCount,
    stopReason:
      lhs.stopReason === "time_budget" || rhs.stopReason === "time_budget" ?
        "time_budget" :
        "drained",
    hasRemainingCandidates:
      lhs.hasRemainingCandidates || rhs.hasRemainingCandidates,
  };
}

/**
 * scheduler 실행 전 초기 요약을 만든다.
 * @return {PurgeDrainSummary} 빈 scheduler 요약
 */
export function initialPurgeDrainSummary(): PurgeDrainSummary {
  return emptyDrainSummary();
}
