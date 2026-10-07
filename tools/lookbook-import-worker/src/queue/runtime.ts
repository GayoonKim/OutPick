import {QUEUE_POLICY} from "./contracts.js";
import {PipelineRuntime} from "../pipeline/resources.js";

// 묶음 하나가 사용하는 시즌 폭·이미지 슬롯·원본 보관량이다.
export function createQueuePipelineRuntime(
  signal?: AbortSignal,
): PipelineRuntime {
  return new PipelineRuntime({
    assets: {kind: "refill", concurrency: null},
    hashes: {kind: "refill",
      concurrency: QUEUE_POLICY.downloadConcurrency},
    limits: {
      download: QUEUE_POLICY.downloadConcurrency,
      transform: QUEUE_POLICY.transformConcurrency,
      upload: QUEUE_POLICY.uploadConcurrency,
      paths: null,
    },
    sourceBufferBudgetBytes: QUEUE_POLICY.sourceReuseBytes,
    signal,
  });
}

export type BatchItemWork<T> = {ordinal: number; value: T};
export type BatchItemResult<T, R> =
  | {ordinal: number; value: T; status: "completed"; result: R}
  | {ordinal: number; value: T; status: "failed"; error: unknown}
  | {ordinal: number; value: T; status: "notStarted"};

// 중단은 신규 시즌 투입을 막고 이미 시작한 작업의 종료를 기다린다.
export async function runQueueBatchItems<T, R>(
  items: readonly BatchItemWork<T>[],
  execute: (item: T, ordinal: number, signal: AbortSignal) => Promise<R>,
  options: {signal: AbortSignal; concurrency?: number},
): Promise<BatchItemResult<T, R>[]> {
  const concurrency = options.concurrency ?? QUEUE_POLICY.seasonConcurrency;
  if (!Number.isSafeInteger(concurrency) || concurrency < 1 ||
      concurrency > QUEUE_POLICY.seasonConcurrency ||
      items.length > QUEUE_POLICY.maxSelectedSeasons ||
      new Set(items.map((item) => item.ordinal)).size !== items.length ||
      items.some((item) => !Number.isSafeInteger(item.ordinal) ||
        item.ordinal < 0)) {
    throw new Error("INVALID_QUEUE_BATCH_ITEMS");
  }
  const results: Array<BatchItemResult<T, R> | undefined> =
    Array.from({length: items.length});
  let cursor = 0;
  async function worker(): Promise<void> {
    for (;;) {
      if (options.signal.aborted) return;
      const index = cursor++;
      const item = items[index];
      if (!item) return;
      try {
        results[index] = {ordinal: item.ordinal, value: item.value,
          status: "completed", result: await execute(item.value, item.ordinal,
            options.signal)};
      } catch (error) {
        results[index] = {ordinal: item.ordinal, value: item.value,
          status: "failed", error};
      }
    }
  }
  const workers = Math.min(concurrency, items.length);
  await Promise.all(Array.from({length: workers}, worker));
  return items.map((item, index) => results[index] ?? {
    ordinal: item.ordinal, value: item.value, status: "notStarted" as const,
  });
}
