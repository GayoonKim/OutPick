import assert from "node:assert/strict";
import {MemoryGuard} from "./memory-supervisor.js";
import type {ContainerMemory} from "./resources.js";

export const ADAPTIVE_AXES =
  ["upload", "transform", "download", "images"] as const;
export type AdaptiveAxis = typeof ADAPTIVE_AXES[number];
export type AdaptiveLimits = Record<AdaptiveAxis, number>;
export const ADAPTIVE_POLICY = Object.freeze({
  version: "adaptive-controller-v1", sampleMs: 100, maxSampleGapMs: 500,
  windowMs: 2000, observeMs: 4000, minCompletions: 4,
  growthRatio: 1.05, latencyRatio: 1.10, cpuGrowthCeiling: 0.80,
  pauseRatio: 0.75, resumeRatio: 0.65, resumeMs: 1000,
  initial: Object.freeze({download: 4, transform: 1, upload: 4, images: 4}),
  maximum: Object.freeze({download: 16, transform: 4, upload: 16, images: 24}),
});
export type AdaptiveDemand = {
  active: number; queued: number; remaining: number;
  canAdmit: boolean; downstreamGrowing: boolean;
};
export type AdaptiveCompletion = {units: number; durationMs: number};
export type AdaptiveSample = {
  // CPU는 AD2 수집기가 직전 구간 사용량을 할당량으로 정규화해 전달한다.
  atMs: number; memory: ContainerMemory | null; cpuRatio: number | null;
  cpuThrottled: boolean; sharpQueued: number;
  demands: Record<AdaptiveAxis, AdaptiveDemand>;
  // 이번 표본 사이에 성공 완료한 작업만 전달한다. 누적 값을 재전달하지 않는다.
  completed: Record<AdaptiveAxis, AdaptiveCompletion[]>;
  transientFailures: {download: number; upload: number};
  fatalReason?: string;
};
type Rate = {count: number; perSecond: number; medianMs: number};
type Rates = Record<AdaptiveAxis, Rate>;
type Probe = {axis: AdaptiveAxis; before: number; atMs: number; base: Rate};
type Decision = {
  atMs: number; reason: string; axis?: AdaptiveAxis;
  targets: AdaptiveLimits; limits: AdaptiveLimits;
  demands?: AdaptiveSample["demands"]; cpuRatio?: number | null;
  memoryRatio?: number; rates?: Rates;
  stopped: string | null; cpuThrottled?: boolean; sharpQueued?: number;
  transientFailures?: AdaptiveSample["transientFailures"];
  memory?: ContainerMemory | null;
};
const emptyCompletions = (): AdaptiveSample["completed"] =>
  ({download: [], transform: [], upload: [], images: []});

// 로컬 제어기다. 실제 계측·메모리 예약·이미지 실행 연결은 AD2에서 주입한다.
export class AdaptiveController {
  private readonly guard: MemoryGuard;
  private targets: AdaptiveLimits = {...ADAPTIVE_POLICY.initial};
  private readonly history: Decision[] = [];
  private sample?: AdaptiveSample;
  private stopped: string | null = null;
  private paused = false;
  private lowSince: number | null = null;
  private windowAt: number;
  private completions = emptyCompletions();
  private probe?: Probe;
  private eligibleAt: number;
  private nextAxis = 0;
  private lastAt: number;

  constructor(startedAt = 0) {
    this.guard = new MemoryGuard(startedAt, ADAPTIVE_POLICY.maxSampleGapMs);
    this.lastAt = startedAt;
    this.windowAt = startedAt;
    this.eligibleAt = startedAt;
  }

  observe(sample: AdaptiveSample) {
    if (this.stopped) return this.snapshot();
    try {
      this.validate(sample);
    } catch {
      this.stop("invalid-sample");
      return this.snapshot();
    }
    const previousLimits = this.snapshot().limits;
    this.lastAt = sample.atMs;
    this.sample = structuredClone(sample);
    this.guard.sample(sample.atMs, sample.memory);
    const stop = this.guard.snapshot().stop;
    if (stop || sample.fatalReason) {
      this.stop(stop?.detail ?? sample.fatalReason!);
      return this.snapshot();
    }
    const ratio = this.memoryRatio();
    if (ratio >= ADAPTIVE_POLICY.pauseRatio) {
      this.lowSince = null;
      if (!this.paused) {
        this.revertProbe();
        this.paused = true;
        this.targets.transform = 1;
        this.record("memory-pause");
      }
    } else if (this.paused) {
      this.lowSince = ratio < ADAPTIVE_POLICY.resumeRatio ?
        this.lowSince ?? sample.atMs : null;
      if (this.lowSince !== null &&
        sample.atMs - this.lowSince >= ADAPTIVE_POLICY.resumeMs) {
        this.paused = false;
        this.eligibleAt = sample.atMs + ADAPTIVE_POLICY.observeMs;
        this.record("memory-resume");
      }
    }
    for (const axis of ["download", "upload"] as const) {
      if (!sample.transientFailures[axis]) continue;
      this.revertProbe();
      this.targets[axis] = Math.max(1, Math.floor(this.targets[axis] / 2));
      this.eligibleAt = sample.atMs + ADAPTIVE_POLICY.observeMs;
      this.record("transient-failure", axis);
    }
    const effective = this.snapshot().limits;
    if (ADAPTIVE_AXES.some((axis) =>
      previousLimits[axis] !== effective[axis])) {
      this.record("admission-change");
    }
    for (const axis of ADAPTIVE_AXES) {
      this.completions[axis].push(...sample.completed[axis]);
      if (this.completions[axis].length > 10000) {
        this.stop("completion-overflow");
        return this.snapshot();
      }
    }
    if (sample.atMs - this.windowAt >= ADAPTIVE_POLICY.windowMs) {
      const rates = this.rates(sample.atMs - this.windowAt);
      this.windowAt = sample.atMs;
      this.completions = emptyCompletions();
      this.decide(sample, rates);
    }
    return this.snapshot();
  }

  // 표본 공급이 멈춰도 외부의 독립 타이머가 이 검사를 호출해야 한다.
  checkTime(atMs: number) {
    this.guard.checkTime(atMs);
    const stop = this.guard.snapshot().stop;
    if (stop) {
      if (Number.isFinite(atMs)) this.lastAt = Math.max(this.lastAt, atMs);
      this.stop(stop.detail);
    }
    return this.snapshot();
  }

  stop(reason: string): void {
    if (this.stopped) return;
    this.stopped = reason;
    this.record("stopped");
  }

  snapshot() {
    const limits = {...this.targets};
    for (const axis of ADAPTIVE_AXES) {
      if (this.stopped || !this.sample ||
        !this.sample.demands[axis].canAdmit ||
        (this.paused && (axis === "download" || axis === "images"))) {
        limits[axis] = 0;
      }
    }
    return {policyVersion: ADAPTIVE_POLICY.version, limits,
      targets: {...this.targets}, paused: this.paused, stopped: this.stopped,
      probe: this.probe ? structuredClone(this.probe) : null,
      memory: this.guard.snapshot()};
  }

  decisions() {
    return structuredClone(this.history);
  }

  private decide(sample: AdaptiveSample, rates: Rates): void {
    if (this.paused || this.stopped) return;
    const probe = this.probe;
    if (probe) {
      if (sample.atMs - probe.atMs < ADAPTIVE_POLICY.observeMs) return;
      const current = rates[probe.axis];
      if (current.count < ADAPTIVE_POLICY.minCompletions) {
        this.record("probe-insufficient", probe.axis, rates);
        return;
      }
      const demand = sample.demands[probe.axis];
      const keep = demand.canAdmit && !demand.downstreamGrowing &&
        current.perSecond >= probe.base.perSecond *
          ADAPTIVE_POLICY.growthRatio &&
        current.medianMs <= probe.base.medianMs *
          ADAPTIVE_POLICY.latencyRatio;
      if (!keep) this.targets[probe.axis] = probe.before;
      this.probe = undefined;
      this.eligibleAt = sample.atMs + ADAPTIVE_POLICY.observeMs;
      this.record(keep ? "probe-kept" : "probe-reverted", probe.axis, rates);
      return;
    }
    if (sample.atMs < this.eligibleAt) return;
    // 한 단계가 계속 바빠도 다른 단계의 탐색 기회를 없애지 않는다.
    for (let offset = 0; offset < ADAPTIVE_AXES.length; offset++) {
      const index = (this.nextAxis + offset) % ADAPTIVE_AXES.length;
      const axis = ADAPTIVE_AXES[index];
      const demand = sample.demands[axis];
      if (!demand.queued || !demand.canAdmit || demand.downstreamGrowing ||
        demand.remaining <= this.targets[axis] ||
        rates[axis].count < ADAPTIVE_POLICY.minCompletions ||
        rates[axis].perSecond <= 0 ||
        this.targets[axis] >= ADAPTIVE_POLICY.maximum[axis]) continue;
      if (axis === "transform" &&
        (sample.cpuRatio! >= ADAPTIVE_POLICY.cpuGrowthCeiling ||
        sample.cpuThrottled || sample.sharpQueued > 0)) continue;
      this.probe = {axis, before: this.targets[axis], atMs: sample.atMs,
        base: {...rates[axis]}};
      this.targets[axis]++;
      this.nextAxis = (index + 1) % ADAPTIVE_AXES.length;
      this.record("probe-start", axis, rates);
      return;
    }
    this.record("hold", undefined, rates);
  }

  private revertProbe(): void {
    if (!this.probe) return;
    const axis = this.probe.axis;
    this.targets[axis] = this.probe.before;
    this.probe = undefined;
    this.record("probe-interrupted", axis);
  }

  private rates(elapsedMs: number): Rates {
    return Object.fromEntries(ADAPTIVE_AXES.map((axis) => {
      const values = this.completions[axis];
      const times = values.map((v) => v.durationMs).sort((a, b) => a - b);
      const middle = Math.floor(times.length / 2);
      return [axis, {count: values.length,
        perSecond: values.reduce((n, v) => n + v.units, 0) *
          1000 / elapsedMs,
        medianMs: times.length ? times.length % 2 ? times[middle] :
          (times[middle - 1] + times[middle]) / 2 : 0}];
    })) as Rates;
  }

  private memoryRatio(): number {
    const memory = this.sample?.memory;
    return memory ? memory.usedBytes / memory.limitBytes : 0;
  }

  private record(reason: string, axis?: AdaptiveAxis,
    rates?: Rates): void {
    if (this.history.length >= 10000) {
      this.stopped = "decision-overflow";
      return;
    }
    const snapshot = this.snapshot();
    this.history.push(structuredClone({atMs: this.lastAt, reason, axis,
      targets: snapshot.targets, limits: snapshot.limits, rates,
      stopped: this.stopped,
      ...(this.sample ? {demands: this.sample.demands,
        cpuRatio: this.sample.cpuRatio, memoryRatio: this.memoryRatio(),
        cpuThrottled: this.sample.cpuThrottled,
        sharpQueued: this.sample.sharpQueued, memory: this.sample.memory,
        transientFailures: this.sample.transientFailures} : {})}));
  }

  private validate(sample: AdaptiveSample): void {
    const nonnegative = (n: number) => Number.isFinite(n) && n >= 0;
    assert.ok(nonnegative(sample.atMs) && sample.atMs >= this.lastAt &&
      (!this.sample || sample.atMs > this.lastAt));
    assert.ok(sample.cpuRatio !== null && nonnegative(sample.cpuRatio));
    assert.equal(typeof sample.cpuThrottled, "boolean");
    assert.ok(Number.isSafeInteger(sample.sharpQueued) &&
      sample.sharpQueued >= 0);
    assert.ok(sample.fatalReason === undefined ||
      (typeof sample.fatalReason === "string" &&
        sample.fatalReason.length > 0));
    for (const axis of ADAPTIVE_AXES) {
      const demand = sample.demands[axis];
      assert.ok([demand.active, demand.queued, demand.remaining]
        .every((n) => Number.isSafeInteger(n) && n >= 0));
      assert.equal(typeof demand.canAdmit, "boolean");
      assert.equal(typeof demand.downstreamGrowing, "boolean");
      assert.ok(Array.isArray(sample.completed[axis]) &&
        sample.completed[axis].length <= 10000);
      assert.ok(sample.completed[axis].every((v) =>
        nonnegative(v.units) && nonnegative(v.durationMs)));
    }
    assert.ok([sample.transientFailures.download,
      sample.transientFailures.upload].every((n) =>
      Number.isSafeInteger(n) && n >= 0));
  }
}
