import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {MemoryGuard} from "./memory-supervisor.js";
import type {ContainerMemory} from "./resources.js";

export type ResourceReading = {
  memory: ContainerMemory; peakBytes: number | null;
  usageMicros: number; throttledMicros: number; cpuCapacity: number;
  quotaCPU: number; cpusetCPU: number;
};
type Read = (path: string) => string;
const integer = (value: string) => {
  assert.match(value.trim(), /^\d+$/);
  const result = Number(value);
  assert.ok(Number.isSafeInteger(result));
  return result;
};
function fields(text: string): Record<string, number> {
  const result: Record<string, number> = {};
  for (const line of text.trim().split("\n")) {
    const [key, value, extra] = line.trim().split(/\s+/);
    assert.ok(key && value && !extra && !(key in result));
    result[key] = integer(value);
  }
  return result;
}
export function cpuSetCount(text: string): number {
  const ranges = text.trim().split(",").map((item) => {
    assert.match(item, /^\d+(-\d+)?$/);
    const [first, last = first] = item.split("-").map(integer);
    assert.ok(first <= last);
    return [first, last];
  }).sort((a, b) => a[0] - b[0]);
  let count = 0;
  let previous = -1;
  for (const [first, last] of ranges) {
    assert.ok(first > previous);
    count += last - first + 1;
    previous = last;
  }
  assert.ok(Number.isSafeInteger(count) && count > 0);
  return count;
}

// 지원하는 컨테이너 루트만 읽는다. 다른 mount/계층을 추측해 사용하지 않는다.
export function readResourceReading(read: Read =
(path) => readFileSync(path, "utf8")): ResourceReading {
  const membership = read("/proc/self/cgroup").trim().split("\n");
  const v2 = membership.some((line) => line.startsWith("0::"));
  let used: number;
  let limit: number;
  let peakPath: string;
  let usage: number;
  let throttled: number;
  let quota: number;
  let period: number;
  let cpuset: number;
  if (v2) {
    assert.deepEqual(membership, ["0::/"]);
    const root = "/sys/fs/cgroup/";
    used = integer(read(root + "memory.current"));
    limit = integer(read(root + "memory.max"));
    peakPath = root + "memory.peak";
    const cpu = fields(read(root + "cpu.stat"));
    usage = cpu.usage_usec;
    throttled = cpu.throttled_usec;
    const max = read(root + "cpu.max").trim().split(/\s+/);
    assert.equal(max.length, 2);
    [quota, period] = max.map(integer);
    cpuset = cpuSetCount(read(root + "cpuset.cpus.effective"));
  } else {
    for (const controller of ["cpu", "cpuacct", "memory", "cpuset"]) {
      assert.ok(membership.some((line) => {
        const [, controllers, path] = line.split(":");
        return controllers.split(",").includes(controller) && path === "/";
      }));
    }
    const root = "/sys/fs/cgroup/";
    used = integer(read(root + "memory/memory.usage_in_bytes"));
    limit = integer(read(root + "memory/memory.limit_in_bytes"));
    peakPath = root + "memory/memory.max_usage_in_bytes";
    usage = integer(read(root + "cpuacct/cpuacct.usage")) / 1000;
    throttled = fields(read(root + "cpu/cpu.stat")).throttled_time / 1000;
    quota = integer(read(root + "cpu/cpu.cfs_quota_us"));
    period = integer(read(root + "cpu/cpu.cfs_period_us"));
    cpuset = cpuSetCount(read(root + "cpuset/cpuset.cpus"));
  }
  assert.ok(limit > 0 && quota > 0 && period > 0);
  assert.ok([usage, throttled].every((n) => Number.isFinite(n) && n >= 0));
  let peak: number | null = null;
  try {
    peak = integer(read(peakPath));
  } catch {
    // 선택적인 최고값만 미지원 시 null로 남기고 사용량으로 대체하지 않는다.
  }
  return {memory: {source: v2 ? "cgroup-v2" : "cgroup-v1",
    usedBytes: used, limitBytes: limit}, peakBytes: peak,
  usageMicros: usage, throttledMicros: throttled,
  quotaCPU: quota / period, cpusetCPU: cpuset,
  cpuCapacity: Math.min(quota / period, cpuset)};
}

export class ResourceFeed {
  private readonly guard: MemoryGuard;
  private previous?: {atMs: number; reading: ResourceReading};
  private readonly window: Array<{atMs: number; reading: ResourceReading}> = [];
  private failure: string | null = null;
  private maxGap = 0;

  constructor(startedAt: number) {
    this.guard = new MemoryGuard(startedAt, 500);
  }

  consume(atMs: number, reading: ResourceReading) {
    if (this.failure) throw new Error(this.failure);
    try {
      assert.ok(Number.isFinite(atMs) && atMs >= 0);
      assert.equal(reading.memory.limitBytes, 2 * 2**30);
      assert.equal(reading.cpuCapacity, 1);
      assert.ok(Number.isFinite(reading.quotaCPU) && reading.quotaCPU > 0);
      assert.ok(Number.isSafeInteger(reading.cpusetCPU) &&
        reading.cpusetCPU > 0);
      assert.equal(reading.cpuCapacity,
        Math.min(reading.quotaCPU, reading.cpusetCPU));
      assert.ok([reading.usageMicros, reading.throttledMicros]
        .every((n) => Number.isFinite(n) && n >= 0));
      if (this.previous) {
        const previous = this.previous;
        assert.ok(atMs > previous.atMs);
        this.maxGap = Math.max(this.maxGap, atMs - previous.atMs);
        assert.ok(reading.usageMicros >= previous.reading.usageMicros &&
          reading.throttledMicros >= previous.reading.throttledMicros);
        for (const field of ["cpuCapacity", "quotaCPU", "cpusetCPU"] as const) {
          assert.equal(reading[field], previous.reading[field]);
        }
      }
      this.guard.sample(atMs, reading.memory);
      assert.equal(this.guard.snapshot().stop, null);
      this.previous = {atMs, reading: structuredClone(reading)};
      this.window.push(this.previous);
      while (this.window.length > 2 && this.window[1].atMs <= atMs - 2000) {
        this.window.shift();
      }
      const first = this.window[0];
      const ready = atMs - first.atMs >= 2000;
      return {atMs, reading: structuredClone(reading), cpuReady: ready,
        cpuRatio: ready ? (reading.usageMicros - first.reading.usageMicros) /
          ((atMs - first.atMs) * 1000 * reading.cpuCapacity) : null,
        throttled: reading.throttledMicros > first.reading.throttledMicros};
    } catch {
      this.failure = this.guard.snapshot().stop?.detail ?? "invalid-resource";
      throw new Error(this.failure);
    }
  }

  checkTime(atMs: number): void {
    this.guard.checkTime(atMs);
    this.failure ??= this.guard.snapshot().stop?.detail ?? null;
    if (this.failure) throw new Error(this.failure);
  }

  snapshot() {
    return {failure: this.failure, maxSampleGapMs: this.maxGap,
      memory: this.guard.snapshot()};
  }
}

type Operation = {id: string; queuedAt: number; startedAt: number | null;
  endedAt: number | null; units: number; outcome: string | null};
export class OperationEvents {
  private readonly all = new Map<string, Operation>();
  private pending: Operation[] = [];

  queue(id: string, atMs: number): void {
    assert.ok(!this.all.has(id) && Number.isFinite(atMs) && atMs >= 0);
    this.all.set(id, {id, queuedAt: atMs, startedAt: null, endedAt: null,
      units: 0, outcome: null});
  }

  start(id: string, atMs: number): void {
    const value = this.all.get(id);
    assert.ok(value && value.startedAt === null &&
      Number.isFinite(atMs) && atMs >= value.queuedAt);
    value.startedAt = atMs;
  }

  finish(id: string, atMs: number, units: number,
    outcome: "succeeded" | "failed" | "cancelled"): void {
    const value = this.all.get(id);
    assert.ok(value && value.startedAt !== null && value.endedAt === null &&
      Number.isFinite(atMs) && atMs >= value.startedAt &&
      Number.isFinite(units) && units >= 0);
    Object.assign(value, {endedAt: atMs, units, outcome});
    this.pending.push(structuredClone(value));
  }

  drain() {
    const pending = this.pending;
    this.pending = [];
    return pending;
  }

  snapshot() {
    return [...this.all.values()].map((v) => ({...v}));
  }
}
