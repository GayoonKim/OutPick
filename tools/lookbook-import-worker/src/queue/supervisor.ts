/* eslint-disable require-jsdoc, max-len */
import {performance} from "node:perf_hooks";
import {MemoryGuard} from "../performance/memory-supervisor.js";
import {readContainerMemorySync, type ContainerMemory} from
  "../performance/resources.js";
import {QUEUE_POLICY} from "./contracts.js";

export type QueueSupervisorReport = {
  startedAt: number;
  sampleCount: number;
  maxMemoryRatio: number | null;
  memorySource: string | null;
  memoryLimitBytes: number | null;
  memoryStop: string | null;
  admissionStop: string | null;
  drainTargetExceeded: boolean;
};

type TimerPort = {
  every: (callback: () => void, intervalMs: number) => () => void;
  after: (callback: () => void, delayMs: number) => () => void;
};

const realTimers: TimerPort = {
  every(callback, intervalMs) {
    const timer = setInterval(callback, intervalMs);
    timer.unref();
    return () => clearInterval(timer);
  },
  after(callback, delayMs) {
    const timer = setTimeout(callback, delayMs);
    timer.unref();
    return () => clearTimeout(timer);
  },
};

// 12분 뒤 신규 시즌을 막고, 14분은 drain 목표 초과로 기록한다.
// in-flight processor를 취소하지 않으며 종료 확인이 없으면 owner를 유지한다.
export class QueueSupervisor {
  readonly signal: AbortSignal;
  private readonly controller = new AbortController();
  private readonly guard: MemoryGuard;
  private readonly startedAt: number;
  private readonly stopTimers: Array<() => void> = [];
  private memoryStop: string | null = null;
  private admissionStop: string | null = null;
  private drainTargetExceeded = false;
  private stopped = false;

  constructor(private readonly options: {
    now?: () => number;
    readMemory?: () => ContainerMemory | null;
    timers?: TimerPort;
  } = {}) {
    const now = options.now ?? (() => performance.now());
    const timers = options.timers ?? realTimers;
    this.startedAt = now();
    this.guard = new MemoryGuard(this.startedAt,
      QUEUE_POLICY.memoryMaxGapMs);
    this.signal = this.controller.signal;
    this.sample();
    this.stopTimers.push(timers.every(() => this.sample(),
      QUEUE_POLICY.memorySampleMs));
    this.stopTimers.push(timers.after(() => this.stopAdmission("TIME_LIMIT"),
      QUEUE_POLICY.stopAdmissionAfterMs));
    this.stopTimers.push(timers.after(() => {
      this.drainTargetExceeded = true;
    }, QUEUE_POLICY.drainTargetAfterMs));
  }

  snapshot(): QueueSupervisorReport {
    const memory = this.guard.snapshot();
    return {
      startedAt: this.startedAt,
      sampleCount: memory.samples,
      maxMemoryRatio: memory.maxRatio,
      memorySource: memory.source,
      memoryLimitBytes: memory.limitBytes,
      memoryStop: this.memoryStop,
      admissionStop: this.admissionStop,
      drainTargetExceeded: this.drainTargetExceeded,
    };
  }

  stop(): QueueSupervisorReport {
    if (!this.stopped) {
      this.stopped = true;
      for (const stop of this.stopTimers) stop();
      this.stopTimers.length = 0;
    }
    return this.snapshot();
  }

  private sample(): void {
    if (this.stopped || this.signal.aborted) return;
    const now = this.options.now ?? (() => performance.now());
    this.guard.checkTime(now());
    let reading: ContainerMemory | null;
    try {
      reading = (this.options.readMemory ?? readContainerMemorySync)();
    } catch {
      reading = null;
    }
    this.guard.sample(now(), reading);
    const stop = this.guard.snapshot().stop;
    if (stop) {
      this.stopForMemory(`${stop.reason}:${stop.detail}`);
      return;
    }
    if (this.guard.snapshot().samples === 1 && reading &&
        reading.usedBytes / reading.limitBytes >=
          QUEUE_POLICY.memoryLimitPercent / 100) {
      this.stopForMemory("memory:startup-high");
    }
  }

  private stopForMemory(reason: string): void {
    this.memoryStop ??= reason;
    this.controller.abort(new Error(`QUEUE_MEMORY_STOP:${reason}`));
  }

  private stopAdmission(reason: string): void {
    if (this.signal.aborted) return;
    this.admissionStop = reason;
    this.controller.abort(new Error(`QUEUE_ADMISSION_STOP:${reason}`));
  }
}
