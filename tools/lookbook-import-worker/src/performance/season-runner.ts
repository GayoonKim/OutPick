import {performance} from "node:perf_hooks";
import {setTimeout} from "node:timers/promises";
import {mapScheduled, validateLaunch} from "../pipeline/scheduling.js";

export type SeasonInput = {id: string; brandID: string};
export type SeasonAttemptOutcome =
  | {status: "succeeded" | "needs-review" | "failed"}
  | {status: "retryable"; retryAfterMs: number};
type AttemptRecord = {
  number: number; startedMs: number; endedMs: number;
  status: SeasonAttemptOutcome["status"] | "aborted" | "operation-error";
};
export type SeasonRecord = SeasonInput & {
  status: "succeeded" | "needs-review" | "failed" | "aborted";
  attempts: AttemptRecord[];
};
export type SeasonExecutionPolicy = {
  order: "parallel" | "serial-per-brand" | "serial-brands";
  concurrency: number | null;
};
export type SeasonEvent = {event: "brand-start" | "brand-end" |
  "attempt-start" | "attempt-end"; brandID: string; seasonID?: string;
  attempt?: number; status?: string; atMs: number};

// 로컬 비교의 실행 순서만 관리한다. 제품 job의 claim이나 배달 횟수는 다루지 않는다.
export async function runSeasons<T extends SeasonInput>(
  inputs: readonly T[], policy: SeasonExecutionPolicy,
  execute: (input: T, context: {attempt: number; signal: AbortSignal}) =>
    Promise<SeasonAttemptOutcome>,
  options: {
    signal: AbortSignal;
    now?: () => number;
    wait?: (ms: number, signal: AbortSignal) => Promise<void>;
    beforeStart?: (input: T) => Promise<void>;
    onEvent?: (event: SeasonEvent) => Promise<void>;
  },
): Promise<SeasonRecord[]> {
  validateLaunch({kind: "refill", concurrency: policy.concurrency});
  const orders = ["parallel", "serial-per-brand", "serial-brands"];
  if (!orders.includes(policy.order) ||
    !inputs.length || inputs.some((item) => !item.id || !item.brandID) ||
    new Set(inputs.map((item) => item.id)).size !== inputs.length) {
    throw new Error("시즌 입력과 실행 순서가 유효하지 않습니다.");
  }
  const {signal} = options;
  const now = options.now ?? (() => performance.now());
  const wait = options.wait ?? ((ms, cancellation) =>
    setTimeout(ms, undefined, {signal: cancellation}));
  const records: SeasonRecord[] = inputs.map(({id, brandID}) =>
    ({id, brandID, status: "aborted", attempts: []}));
  const groups = new Map<string, number[]>();
  const remaining = new Map<string, number>();
  inputs.forEach((item, index) => {
    const key = policy.order === "parallel" ? item.id : item.brandID;
    const group = groups.get(key) ?? [];
    group.push(index);
    groups.set(key, group);
    remaining.set(item.brandID, (remaining.get(item.brandID) ?? 0) + 1);
  });
  const admitted = new Map<string, Promise<void>>();
  const emit = (event: Omit<SeasonEvent, "atMs">) =>
    options.onEvent?.({...event, atMs: now()}) ?? Promise.resolve();
  async function runOne(index: number): Promise<void> {
    const record = records[index];
    if (signal.aborted) return;
    await options.beforeStart?.(inputs[index]);
    if (signal.aborted) return;
    if (!admitted.has(record.brandID)) {
      admitted.set(record.brandID, emit({event: "brand-start",
        brandID: record.brandID}));
    }
    await admitted.get(record.brandID);
    try {
      for (let attempt = 1; attempt <= 5; attempt++) {
        if (signal.aborted) return;
        const entry: AttemptRecord = {number: attempt,
          startedMs: now(), endedMs: 0, status: "operation-error"};
        record.attempts.push(entry);
        let outcome: SeasonAttemptOutcome;
        try {
          await emit({event: "attempt-start", brandID: record.brandID,
            seasonID: record.id, attempt});
          signal.throwIfAborted();
          outcome = await execute(inputs[index], {attempt, signal});
          if (!outcome || !["succeeded", "needs-review", "failed", "retryable"]
            .includes(outcome.status) || (outcome.status === "retryable" &&
          (!Number.isSafeInteger(outcome.retryAfterMs) ||
            outcome.retryAfterMs < 0))) {
            throw new Error("시즌 시도 결과가 유효하지 않습니다.");
          }
          entry.status = outcome.status;
        } catch {
          entry.status = signal.aborted ? "aborted" : "operation-error";
          record.status = signal.aborted ? "aborted" : "failed";
          return;
        } finally {
          entry.endedMs = now();
          await emit({event: "attempt-end", brandID: record.brandID,
            seasonID: record.id, attempt, status: entry.status});
        }
        if (signal.aborted) return;
        if (outcome.status !== "retryable") {
          record.status = outcome.status;
          return;
        }
        if (attempt === 5) {
          record.status = "failed";
          return;
        }
        try {
          await wait(outcome.retryAfterMs, signal);
        } catch {
          record.status = signal.aborted ? "aborted" : "failed";
          return;
        }
      }
    } finally {
      const left = (remaining.get(record.brandID) ?? 1) - 1;
      remaining.set(record.brandID, left);
      if (left === 0) await emit({event: "brand-end", brandID: record.brandID});
    }
  }
  // 취소 때도 이미 시작한 시도와 형제 브랜드의 종료를 기다린다.
  try {
    await mapScheduled([...groups.values()],
      {kind: "refill", concurrency: policy.order === "serial-brands" ?
        1 : policy.concurrency}, async (indices) => {
        if (policy.order === "serial-brands") {
          await mapScheduled(indices, {kind: "refill",
            concurrency: policy.concurrency}, runOne, signal);
          return;
        }
        for (const index of indices) {
          if (signal.aborted) break;
          await runOne(index);
        }
      }, signal);
  } catch (error) {
    if (!signal.aborted) throw error;
  }
  return records;
}
