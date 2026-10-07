import {performance} from "node:perf_hooks";
import {type LaunchPolicy, validateLaunch} from "./scheduling.js";
import {SourceBufferStore} from "./source-buffer-store.js";

export type ResourceStage = "download" | "transform" | "upload" | "paths";
export type StageLimits = Record<ResourceStage, number | null>;
type Waiter = {
  resolve: () => void; reject: (error: unknown) => void;
  signal?: AbortSignal; onAbort?: () => void;
};

export class Slots {
  private active = 0;
  private peakActive = 0;
  private peakQueued = 0;
  private started = 0;
  private completed = 0;
  private failed = 0;
  private waitMs = 0;
  private readonly queue: Waiter[] = [];

  constructor(private limit: number | null,
    private readonly adjustable = false) {
    if (limit !== null && (!Number.isSafeInteger(limit) || limit < 1)) {
      throw new Error("공용 슬롯 수는 양의 정수 또는 null이어야 합니다.");
    }
  }

  setLimit(limit: number): void {
    if (!this.adjustable || !Number.isSafeInteger(limit) || limit < 0) {
      throw new Error("명시적 가변 슬롯만 0 이상의 정수로 변경할 수 있습니다.");
    }
    this.limit = limit;
    this.pump();
  }

  async run<T>(operation: () => Promise<T>, signal?: AbortSignal): Promise<T> {
    const start = performance.now();
    await this.acquire(signal);
    this.waitMs += performance.now() - start;
    try {
      this.started++;
      signal?.throwIfAborted();
      const result = await operation();
      this.completed++;
      return result;
    } catch (error) {
      this.failed++;
      throw error;
    } finally {
      this.release();
    }
  }

  snapshot() {
    return {
      limit: this.limit, active: this.active, queued: this.queue.length,
      peakActive: this.peakActive, peakQueued: this.peakQueued,
      started: this.started, completed: this.completed, failed: this.failed,
      waitMs: this.waitMs,
    };
  }

  private acquire(signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    if (this.limit === null || this.active < this.limit) {
      this.active++;
      this.peakActive = Math.max(this.peakActive, this.active);
      return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
      const waiter: Waiter = {resolve, reject, signal};
      waiter.onAbort = () => {
        const index = this.queue.indexOf(waiter);
        if (index < 0) return;
        this.queue.splice(index, 1);
        reject(signal?.reason);
      };
      signal?.addEventListener("abort", waiter.onAbort, {once: true});
      this.queue.push(waiter);
      this.peakQueued = Math.max(this.peakQueued, this.queue.length);
    });
  }

  private release(): void {
    this.active--;
    this.pump();
  }

  private pump(): void {
    while (this.queue.length &&
      (this.limit === null || this.active < this.limit)) {
      const next = this.queue.shift()!;
      if (next.onAbort) next.signal?.removeEventListener("abort", next.onAbort);
      this.active++;
      this.peakActive = Math.max(this.peakActive, this.active);
      next.resolve();
    }
  }
}

// 호출자별로 새로 만들지 않고 한 인스턴스의 시즌들이 같은 객체를 공유한다.
export class PipelineRuntime {
  readonly signal?: AbortSignal;
  readonly sourceBuffers?: SourceBufferStore;
  readonly assets: LaunchPolicy;
  readonly hashes: LaunchPolicy;
  private readonly slots: Record<ResourceStage, Slots>;

  constructor(config: {
    assets: LaunchPolicy; hashes: LaunchPolicy; limits: StageLimits;
    sourceBufferBudgetBytes?: number | null;
    signal?: AbortSignal;
    adjustableLimits?: boolean;
  }) {
    validateLaunch(config.assets);
    validateLaunch(config.hashes);
    this.signal = config.signal;
    this.assets = Object.freeze({...config.assets});
    this.hashes = Object.freeze({...config.hashes});
    this.sourceBuffers = config.sourceBufferBudgetBytes === undefined ?
      undefined : new SourceBufferStore(config.sourceBufferBudgetBytes);
    this.slots = {
      download: new Slots(config.limits.download, config.adjustableLimits),
      transform: new Slots(config.limits.transform, config.adjustableLimits),
      upload: new Slots(config.limits.upload, config.adjustableLimits),
      paths: new Slots(config.limits.paths, config.adjustableLimits),
    };
  }

  setStageLimit(stage: ResourceStage, limit: number): void {
    this.slots[stage].setLimit(limit);
  }

  run<T>(
    stage: ResourceStage, operation: () => Promise<T>, signal?: AbortSignal,
  ) {
    const combined = signal && this.signal ?
      AbortSignal.any([signal, this.signal]) : signal ?? this.signal;
    return this.slots[stage].run(operation, combined);
  }

  snapshot() {
    return Object.fromEntries(Object.entries(this.slots)
      .map(([stage, slots]) => [stage, slots.snapshot()]));
  }
}

export function inStage<T>(
  runtime: PipelineRuntime | undefined, stage: ResourceStage,
  operation: () => Promise<T>,
): Promise<T> {
  return runtime ? runtime.run(stage, operation) : operation();
}
