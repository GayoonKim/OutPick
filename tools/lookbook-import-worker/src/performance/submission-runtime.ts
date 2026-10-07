import assert from "node:assert/strict";
import {AsyncLocalStorage} from "node:async_hooks";
import {PipelineRuntime, type ResourceStage} from "../pipeline/resources.js";
import {ReuseTrace} from "./reuse-trace.js";

type Pending = {rank: number; start: () => void; cancel: () => void};

// 로컬 유한 입력 실험 전용이다. 준비되지 않은 앞 시즌을 기다리지 않는다.
export class ReadySeasonQueue {
  private readonly pending: Pending[] = [];
  private stats = {limit: 1, active: 0, queued: 0, peakActive: 0,
    peakQueued: 0, started: 0, completed: 0, failed: 0, waitMs: 0};

  constructor(private readonly adjustable = false, initialLimit = 1) {
    assert.ok(Number.isSafeInteger(initialLimit) && initialLimit >= 1);
    this.stats.limit = initialLimit;
  }

  setLimit(limit: number): void {
    assert.ok(this.adjustable && Number.isSafeInteger(limit) && limit >= 0);
    this.stats.limit = limit;
    this.pump();
  }

  run<T>(rank: number, work: () => Promise<T>, signal?: AbortSignal):
    Promise<T> {
    assert.ok(Number.isSafeInteger(rank) && rank >= 0);
    signal?.throwIfAborted();
    const submitted = performance.now();
    const restoreContext = AsyncLocalStorage.snapshot();
    return new Promise<T>((resolve, reject) => {
      const entry: Pending = {rank, cancel: () => {
        const index = this.pending.indexOf(entry);
        if (index < 0) return;
        this.pending.splice(index, 1);
        signal?.removeEventListener("abort", entry.cancel);
        reject(signal?.reason);
      }, start: () => restoreContext(() => {
        signal?.removeEventListener("abort", entry.cancel);
        this.stats.active++;
        this.stats.peakActive = Math.max(this.stats.peakActive,
          this.stats.active);
        this.stats.started++;
        this.stats.waitMs += performance.now() - submitted;
        // 선택과 실행 시작 사이에 별도의 비동기 대기를 넣지 않는다.
        void (async () => {
          try {
            signal?.throwIfAborted();
            const result = await work();
            this.stats.completed++;
            resolve(result);
          } catch (error) {
            this.stats.failed++;
            reject(error);
          } finally {
            this.stats.active--;
            this.pump();
          }
        })();
      })};
      this.pending.push(entry);
      signal?.addEventListener("abort", entry.cancel, {once: true});
      if (this.stats.active) {
        this.stats.peakQueued = Math.max(this.stats.peakQueued,
          this.pending.length);
      }
      this.pump();
    });
  }

  snapshot() {
    return {...this.stats, queued: this.pending.length};
  }

  private pump(): void {
    while (this.stats.active < this.stats.limit && this.pending.length) {
      let selected = 0;
      for (let index = 1; index < this.pending.length; index++) {
        if (this.pending[index].rank < this.pending[selected].rank) {
          selected = index;
        }
      }
      this.pending.splice(selected, 1)[0].start();
    }
  }
}

export class SubmissionRuntime extends PipelineRuntime {
  private readonly context = new AsyncLocalStorage<number>();
  private readonly priority: ReadySeasonQueue;

  constructor(config: ConstructorParameters<typeof PipelineRuntime>[0],
    private readonly trace: ReuseTrace, private readonly prioritized: boolean) {
    super(config);
    assert.ok(config.limits.transform !== null);
    this.priority = new ReadySeasonQueue(config.adjustableLimits,
      config.limits.transform);
  }

  override setStageLimit(stage: ResourceStage, limit: number): void {
    if (this.prioritized && stage === "transform") {
      this.priority.setLimit(limit);
    } else super.setStageLimit(stage, limit);
  }

  withSeason<T>(rank: number, work: () => Promise<T>): Promise<T> {
    return this.context.run(rank, work);
  }

  override run<T>(stage: ResourceStage, work: () => Promise<T>,
    signal?: AbortSignal): Promise<T> {
    const combined = signal && this.signal ?
      AbortSignal.any([signal, this.signal]) : signal ?? this.signal;
    return this.trace.stage(stage, (operation) => {
      if (!this.prioritized || stage !== "transform") {
        return super.run(stage, operation, signal);
      }
      const rank = this.context.getStore();
      assert.ok(rank !== undefined);
      // 변환 슬롯을 대체한다. 기존 슬롯과 겹쳐 대기 시간을 이중 계산하지 않는다.
      return this.priority.run(rank, operation, combined);
    }, work);
  }

  override snapshot() {
    return {...super.snapshot(), ...(this.prioritized ?
      {transform: this.priority.snapshot()} : {})};
  }
}
