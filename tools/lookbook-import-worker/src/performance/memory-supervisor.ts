import {performance} from "node:perf_hooks";
import {readContainerMemory, type ContainerMemory} from "./resources.js";

export type MemoryStop = {
  reason: "memory" | "environment";
  detail: "sustained-high" | "missing-or-invalid" | "sample-gap" |
    "container-changed" | "invalid-clock";
  atMs: number;
};

// RSS 대신 컨테이너 전체 표본을 사용한다. 표본 사이의 실제 연속성을 보장하지는 않는다.
export class MemoryGuard {
  private lastAt: number;
  private highSince: number | null = null;
  private container: ContainerMemory | null = null;
  private samples = 0;
  private maxRatio = 0;
  private stopped: MemoryStop | null = null;

  constructor(private readonly startedAt: number,
    private readonly maxSampleGapMs: number) {
    if (!Number.isFinite(startedAt) || startedAt < 0 ||
      !Number.isSafeInteger(maxSampleGapMs) ||
      maxSampleGapMs < 100 || maxSampleGapMs >= 1000) {
      throw new Error("표본 간격 허용값은 100ms 이상 1초 미만이어야 합니다.");
    }
    this.lastAt = startedAt;
  }

  checkTime(at: number): void {
    if (this.stopped) return;
    if (!Number.isFinite(at) || at < this.lastAt) {
      this.stop("environment", "invalid-clock", this.lastAt);
    } else if (at - this.lastAt > this.maxSampleGapMs) {
      this.stop("environment", "sample-gap", at);
    }
  }

  sample(at: number, value: ContainerMemory | null): void {
    this.checkTime(at);
    if (this.stopped) return;
    if (!value || !["cgroup-v1", "cgroup-v2"].includes(value.source) ||
      !Number.isSafeInteger(value.usedBytes) || value.usedBytes < 0 ||
      !Number.isSafeInteger(value.limitBytes) || value.limitBytes <= 0) {
      this.stop("environment", "missing-or-invalid", at);
      return;
    }
    if (this.container && (this.container.source !== value.source ||
      this.container.limitBytes !== value.limitBytes)) {
      this.stop("environment", "container-changed", at);
      return;
    }
    this.container = {...value};
    this.lastAt = at;
    this.samples++;
    const ratio = value.usedBytes / value.limitBytes;
    this.maxRatio = Math.max(this.maxRatio, ratio);
    if (ratio < 0.85) {
      this.highSince = null;
    } else {
      this.highSince ??= at;
      if (at - this.highSince >= 1000) {
        this.stop("memory", "sustained-high", at);
      }
    }
  }

  snapshot() {
    return {
      sampleIntervalMs: 100, maxSampleGapMs: this.maxSampleGapMs,
      thresholdRatio: 0.85, sustainedMs: 1000,
      samples: this.samples, maxRatio: this.samples ? this.maxRatio : null,
      source: this.container?.source ?? null,
      limitBytes: this.container?.limitBytes ?? null,
      lastSampleMs: this.samples ? this.lastAt - this.startedAt : null,
      highSinceMs: this.highSince === null ? null :
        this.highSince - this.startedAt,
      stop: this.stopped ? {...this.stopped} : null,
    };
  }

  private stop(reason: MemoryStop["reason"], detail: MemoryStop["detail"],
    at: number): void {
    this.stopped = {reason, detail, atMs: at - this.startedAt};
  }
}

type MemoryReport = ReturnType<MemoryGuard["snapshot"]>;
export type SupervisedResult<T> = {
  status: "completed"; value: T; memory: MemoryReport;
} | {
  status: "failed"; error: unknown; memory: MemoryReport;
} | {
  status: "unavailable" | "stopped";
  operation: "not-started" | "returned" | "threw";
  value?: T; error?: unknown; memory: MemoryReport;
};

export async function superviseMemory<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  options: {
    maxSampleGapMs: number;
    readMemory?: () => Promise<ContainerMemory | null>;
    clock?: {now: () => number;
      every: (tick: () => void, intervalMs: number) => () => void};
  },
): Promise<SupervisedResult<T>> {
  const clock = options.clock ?? {now: () => performance.now(),
    every(tick: () => void, ms: number) {
      const timer = setInterval(tick, ms);
      return () => clearInterval(timer);
    }};
  const guard = new MemoryGuard(clock.now(), options.maxSampleGapMs);
  const controller = new AbortController();
  let notifyStopped!: () => void;
  const stopped = new Promise<void>((resolve) => {
    notifyStopped = resolve;
  });
  function checkStop(): void {
    const stop = guard.snapshot().stop;
    if (stop && !controller.signal.aborted) {
      controller.abort(new Error(`실험 중단: ${stop.detail}`));
      notifyStopped();
    }
  }
  let pending: Promise<void> | null = null;
  function probe(): Promise<void> {
    if (pending) return pending;
    pending = (async () => {
      let value: ContainerMemory | null;
      try {
        value = await (options.readMemory ?? readContainerMemory)();
      } catch {
        value = null;
      }
      // 중단 뒤 늦게 도착한 표본은 결과를 정상으로 되돌리지 않는다.
      guard.sample(clock.now(), value);
      checkStop();
    })().finally(() => {
      pending = null;
    });
    return pending;
  }
  const stopTimer = clock.every(() => {
    guard.checkTime(clock.now());
    checkStop();
    if (!controller.signal.aborted) void probe();
  }, 100);
  try {
    await Promise.race([probe(), stopped]);
    if (controller.signal.aborted) {
      return {status: "unavailable", operation: "not-started",
        memory: guard.snapshot()};
    }
    let result: {status: "completed"; value: T} |
      {status: "failed"; error: unknown};
    try {
      result = {status: "completed", value: await operation(controller.signal)};
    } catch (error) {
      result = {status: "failed", error};
    }
    // 중단 신호는 신규 실행을 막는다. 실행 중 SDK/변환의 실제 종료는 기다린다.
    if (!controller.signal.aborted) {
      await Promise.race([pending ?? Promise.resolve(), stopped]);
      if (!controller.signal.aborted) await Promise.race([probe(), stopped]);
    }
    const memory = guard.snapshot();
    if (controller.signal.aborted) {
      return {status: "stopped",
        operation: result.status === "completed" ? "returned" : "threw",
        ...(result.status === "completed" ? {value: result.value} :
          {error: result.error}), memory};
    }
    return {...result, memory};
  } finally {
    stopTimer();
  }
}
