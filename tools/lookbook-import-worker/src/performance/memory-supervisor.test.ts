import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {MemoryGuard, superviseMemory} from "./memory-supervisor.js";
import {type ContainerMemory} from "./resources.js";
import {runSeasons} from "./season-runner.js";

const memory = (usedBytes = 85): ContainerMemory =>
  ({source: "cgroup-v2", usedBytes, limitBytes: 100});
function clock() {
  let at = 0;
  let tick: (() => void) | null = null;
  return {
    now: () => at,
    every(callback: () => void, ms: number) {
      assert.equal(ms, 100);
      tick = callback;
      return () => {
        tick = null;
      };
    },
    active: () => tick !== null,
    async advance(ms: number) {
      at += ms;
      tick?.();
      await setImmediate();
    },
  };
}

test("메모리 85퍼센트는 유효 표본에서 1초 지속할 때만 중단한다", () => {
  const guard = new MemoryGuard(0, 500);
  for (let at = 0; at < 1000; at += 100) guard.sample(at, memory());
  assert.equal(guard.snapshot().stop, null);
  guard.sample(1000, memory());
  assert.deepEqual(guard.snapshot().stop,
    {reason: "memory", detail: "sustained-high", atMs: 1000});
  guard.sample(1100, memory(0));
  assert.equal(guard.snapshot().samples, 11);
});

test("메모리 임계 미만 표본은 지속 구간을 새로 시작하게 한다", () => {
  const guard = new MemoryGuard(0, 500);
  for (let at = 0; at < 500; at += 100) guard.sample(at, memory());
  guard.sample(500, memory(84));
  for (let at = 600; at < 1600; at += 100) guard.sample(at, memory());
  assert.equal(guard.snapshot().stop, null);
  guard.sample(1600, memory());
  assert.equal(guard.snapshot().stop?.atMs, 1600);
});

test("표본 누락 지연과 컨테이너 변경은 메모리 안전 미검증으로 중단한다", () => {
  for (const value of [null, memory(-1), {...memory(), limitBytes: 0},
    {...memory(), usedBytes: NaN}]) {
    const guard = new MemoryGuard(0, 500);
    guard.sample(0, value);
    assert.equal(guard.snapshot().stop?.detail, "missing-or-invalid");
  }
  const gap = new MemoryGuard(0, 500);
  gap.sample(0, memory());
  gap.checkTime(500);
  assert.equal(gap.snapshot().stop, null);
  gap.sample(501, memory(0));
  assert.equal(gap.snapshot().stop?.detail, "sample-gap");
  for (const value of [{...memory(), limitBytes: 101},
    {...memory(), source: "cgroup-v1" as const}]) {
    const guard = new MemoryGuard(0, 500);
    guard.sample(0, memory());
    guard.sample(100, value);
    assert.equal(guard.snapshot().stop?.detail, "container-changed");
  }
  const invalidClock = new MemoryGuard(1, 500);
  invalidClock.sample(0, memory());
  assert.equal(invalidClock.snapshot().stop?.detail, "invalid-clock");
  for (const gap of [0, 99, 1000, NaN]) {
    assert.throws(() => new MemoryGuard(0, gap));
  }
});

test("중단 감독은 초기 메모리 미지원이면 실험을 시작하지 않는다", async () => {
  for (const readMemory of [async () => null, async () => {
    throw new Error("읽기 실패");
  }]) {
    const time = clock();
    const result = await superviseMemory(async () => {
      assert.fail("환경 미준비에서 실험을 실행하면 안 된다");
    }, {maxSampleGapMs: 500, readMemory, clock: time});
    assert.equal(result.status, "unavailable");
    assert.equal(result.memory.stop?.reason, "environment");
    assert.equal(time.active(), false);
  }
});

test("멈춘 메모리 읽기는 중복 요청 없이 중단하고 늦은 표본을 무시한다",
  async () => {
    const time = clock();
    let reads = 0;
    let release!: (value: ContainerMemory) => void;
    const pending = new Promise<ContainerMemory>((resolve) => {
      release = resolve;
    });
    const work = superviseMemory(async () => assert.fail("실행 불가"),
      {maxSampleGapMs: 500, clock: time, readMemory: () => {
        reads++;
        return pending;
      }});
    for (let index = 0; index < 6; index++) await time.advance(100);
    const result = await work;
    assert.equal(result.status, "unavailable");
    assert.equal(reads, 1);
    assert.equal(result.memory.stop?.detail, "sample-gap");
    assert.equal(time.active(), false);
    release(memory(0));
    await setImmediate();
    assert.equal(result.memory.samples, 0);
  });

test("중단 감독은 신호 후에도 실행 중 작업의 종료까지 결과를 확정하지 않는다",
  async () => {
    const time = clock();
    let release!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    let signal: AbortSignal | undefined;
    let ended = false;
    const work = superviseMemory(async (cancellation) => {
      signal = cancellation;
      await pending;
      return 42;
    }, {maxSampleGapMs: 500, clock: time, readMemory: async () => memory()})
      .then((result) => {
        ended = true;
        return result;
      });
    await setImmediate();
    for (let index = 0; index < 10; index++) await time.advance(100);
    assert.equal(signal?.aborted, true);
    assert.equal(ended, false);
    release();
    const result = await work;
    assert.equal(result.status, "stopped");
    assert.equal(result.memory.stop?.reason, "memory");
    assert.equal(time.active(), false);
    if (result.status === "stopped") {
      assert.equal(result.operation, "returned");
      assert.equal(result.value, 42);
    }
  });

test("중단 감독은 정상 실패와 종료 표본의 환경 실패를 구분한다", async () => {
  const error = new Error("작업 실패");
  const time = clock();
  const failed = await superviseMemory(async () => {
    throw error;
  }, {maxSampleGapMs: 500, clock: time, readMemory: async () => memory(20)});
  assert.equal(failed.status, "failed");
  if (failed.status === "failed") assert.equal(failed.error, error);
  assert.equal(failed.memory.samples, 2);
  let reads = 0;
  const stopped = await superviseMemory(async () => "returned",
    {maxSampleGapMs: 500, clock: clock(), readMemory: async () =>
      ++reads === 1 ? memory(20) : null});
  assert.equal(stopped.status, "stopped");
  assert.equal(stopped.memory.stop?.reason, "environment");
  const success = await superviseMemory(async () => 123,
    {maxSampleGapMs: 500, clock: clock(), readMemory: async () => memory(20)});
  assert.equal(success.status, "completed");
  assert.equal(success.memory.stop, null);
});

test("중단 감독과 시즌 실행기는 미시작 시즌을 성공 분모로 바꾸지 않는다",
  async () => {
    const time = clock();
    let release!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    const work = superviseMemory((signal) => runSeasons([
      {id: "first", brandID: "a"}, {id: "next", brandID: "a"},
    ], {order: "serial-per-brand", concurrency: null}, async () => {
      await pending;
      return {status: "succeeded"};
    }, {signal}), {maxSampleGapMs: 500, clock: time,
      readMemory: async () => memory()});
    await setImmediate();
    for (let index = 0; index < 10; index++) await time.advance(100);
    release();
    const result = await work;
    assert.equal(result.status, "stopped");
    if (result.status === "stopped") {
      assert.deepEqual(result.value?.map((x) => x.status),
        ["aborted", "aborted"]);
      assert.deepEqual(result.value?.map((x) => x.attempts.length), [1, 0]);
    }
  });
