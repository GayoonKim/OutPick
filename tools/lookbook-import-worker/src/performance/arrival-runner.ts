import {performance} from "node:perf_hooks";
import {setTimeout} from "node:timers/promises";
import {runSeasons, type SeasonInput, type SeasonExecutionPolicy,
  type SeasonAttemptOutcome, type SeasonEvent} from "./season-runner.js";

export const BRAND_ARRIVAL_INTERVAL_MS = 100;
export type BrandArrival = {
  brandID: string; scheduledMs: number; arrivedMs: number | null;
};

// 실험 안의 도착을 재현한다. 제품 HTTP 접수나 분산 대기열이 아니다.
export async function runArrivingSeasons<T extends SeasonInput>(
  inputs: readonly T[], policy: SeasonExecutionPolicy,
  execute: (input: T, context: {attempt: number; signal: AbortSignal}) =>
    Promise<SeasonAttemptOutcome>,
  options: {
    signal: AbortSignal;
    now?: () => number;
    arrivalWait?: (ms: number, signal: AbortSignal) => Promise<void>;
    retryWait?: (ms: number, signal: AbortSignal) => Promise<void>;
    onEvent?: (event: SeasonEvent) => Promise<void>;
  },
) {
  const now = options.now ?? (() => performance.now());
  const wait = options.arrivalWait ?? ((ms, signal) =>
    setTimeout(ms, undefined, {signal}));
  const cleanup = new AbortController();
  const signal = AbortSignal.any([options.signal, cleanup.signal]);
  const originMs = now();
  const arrivals: BrandArrival[] = [...new Set(inputs.map((s) => s.brandID))]
    .map((brandID, index) => ({brandID,
      scheduledMs: originMs + index * BRAND_ARRIVAL_INTERVAL_MS,
      arrivedMs: null}));
  let timerError: unknown;
  let timerFailed = false;
  // 슬롯이 차 있어도 접수 시각은 독립적으로 기록한다.
  const gates = new Map(arrivals.map((arrival) => [arrival.brandID,
    (async () => {
      try {
        signal.throwIfAborted();
        while (now() < arrival.scheduledMs) {
          const before = now();
          await wait(Math.ceil(arrival.scheduledMs - before), signal);
          signal.throwIfAborted();
          if (now() <= before) {
            throw new Error("접수 타이머가 예약 시각 전에 진행 없이 종료됐습니다.");
          }
        }
        signal.throwIfAborted();
        if (now() < arrival.scheduledMs) {
          throw new Error("접수 타이머가 예약 시각 전에 종료됐습니다.");
        }
        arrival.arrivedMs = now();
      } catch (error) {
        if (!signal.aborted) {
          timerFailed = true;
          timerError = error;
          cleanup.abort(error);
        }
      }
    })()]));
  try {
    const seasons = await runSeasons(inputs, policy, execute, {
      signal, now, wait: options.retryWait, onEvent: options.onEvent,
      beforeStart: async (input) => {
        await gates.get(input.brandID);
        signal.throwIfAborted();
      },
    });
    if (timerFailed) throw timerError;
    return {originMs, arrivals, seasons};
  } finally {
    cleanup.abort();
    await Promise.all(gates.values());
  }
}
