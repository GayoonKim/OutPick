import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {runArrivingSeasons} from "./arrival-runner.js";

const inputs = Array.from("ABCDEFGHIJ").flatMap((brandID, index) =>
  Array.from({length: index === 0 ? 8 : index === 1 ? 2 : 1}, (_, i) =>
    ({id: `${brandID}-${i}`, brandID})));
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}
function clock() {
  let current = 1000;
  type Timer = {at: number; finish: () => void};
  const timers = new Set<Timer>();
  const wait = (ms: number, signal: AbortSignal) =>
    new Promise<void>((resolve, reject) => {
      const clean = () => {
        timers.delete(timer); signal.removeEventListener("abort", abort);
      };
      const abort = () => {
        clean(); reject(signal.reason);
      };
      const timer = {at: current + ms, finish: () => {
        clean(); resolve();
      }};
      timers.add(timer);
      signal.addEventListener("abort", abort, {once: true});
      if (signal.aborted) abort();
    });
  return {now: () => current, wait, pending: () => timers.size,
    advance: async (ms: number) => {
      current += ms;
      for (const timer of [...timers]) {
        if (timer.at <= current) timer.finish();
      }
      await setImmediate();
    }};
}

test("TB03 백 밀리초 접수는 직렬 병렬과 합산 한도에서 조기 실행을 막는다",
  async () => {
    for (const order of ["serial-brands", "parallel"] as const) {
      for (const concurrency of [6, null]) {
        const time = clock(); const release = deferred();
        const starts = new Map<string, number>();
        const ended = new Set<string>();
        let active = 0; let peak = 0;
        const work = runArrivingSeasons(inputs, {order, concurrency},
          async (item) => {
            assert.ok(time.now() >= 1000 +
              (item.brandID.charCodeAt(0) - 65) * 100);
            if (order === "serial-brands") {
              assert.ok(inputs.filter((s) => s.brandID < item.brandID)
                .every((s) => ended.has(s.id)));
            }
            starts.set(item.id, time.now()); active++;
            peak = Math.max(peak, active);
            await release.promise;
            await setImmediate();
            active--; ended.add(item.id);
            return {status: "succeeded"};
          }, {signal: new AbortController().signal, now: time.now,
            arrivalWait: time.wait});
        try {
          await setImmediate();
          assert.equal(starts.size, concurrency ?? 8);
          for (let index = 1; index <= 9; index++) {
            await time.advance(99);
            assert.equal(starts.has(`${String.fromCharCode(65 + index)}-0`),
              false);
            await time.advance(1);
            const expected = concurrency ??
              (order === "serial-brands" ? 8 : 9 + index);
            assert.equal(starts.size, expected);
          }
        } finally {
          release.resolve();
        }
        const result = await work;
        assert.deepEqual(result.arrivals.map((a) => a.arrivedMs),
          Array.from({length: 10}, (_, i) => 1000 + i * 100));
        assert.equal(result.seasons.length, 18);
        assert.ok(result.seasons.every((s) => s.status === "succeeded"));
        assert.equal(peak, concurrency ??
          (order === "serial-brands" ? 8 : 18));
        assert.equal(active, 0); assert.equal(time.pending(), 0);
      }
    }
  });

test("TB04 접수 대기 중 취소는 타이머를 회수하고 실행 중 시즌 정리를 기다린다",
  async () => {
    for (const order of ["serial-brands", "parallel"] as const) {
      const time = clock(); const release = deferred();
      const controller = new AbortController();
      const started: string[] = [];
      let complete = false;
      const work = runArrivingSeasons(inputs, {order, concurrency: null},
        async ({brandID}) => {
          started.push(brandID); await release.promise;
          return {status: "succeeded"};
        }, {signal: controller.signal, now: time.now, arrivalWait: time.wait});
      void work.then(() => {
        complete = true;
      });
      await setImmediate(); await time.advance(50);
      controller.abort(); await setImmediate();
      assert.equal(complete, false);
      assert.equal(time.pending(), 0);
      assert.deepEqual(started, Array(8).fill("A"));
      release.resolve();
      const result = await work;
      assert.ok(result.seasons.every((s) => s.status === "aborted"));
      assert.ok(result.seasons.filter((s) => s.brandID !== "A")
        .every((s) => s.attempts.length === 0));
      assert.ok(result.arrivals.slice(1).every((a) => a.arrivedMs === null));
    }
  });

test("TB05 지연된 접수 시각은 예약과 분리되고 타이머 실패는 성공이 아니다",
  async () => {
    const time = clock();
    const work = runArrivingSeasons(inputs,
      {order: "parallel", concurrency: null}, async () =>
        ({status: "succeeded"}), {signal: new AbortController().signal,
        now: time.now, arrivalWait: time.wait});
    await time.advance(900);
    const result = await work;
    assert.equal(result.arrivals[1].scheduledMs, 1100);
    assert.equal(result.arrivals[1].arrivedMs, 1900);
    assert.equal(time.pending(), 0);
    await assert.rejects(runArrivingSeasons(inputs,
      {order: "parallel", concurrency: null}, async () =>
        ({status: "succeeded"}), {signal: new AbortController().signal,
        now: () => 1000, arrivalWait: async () => {
          return;
        }}), /예약 시각/);
  });

test("TB06 시작 전 취소는 접수와 시즌 시도를 만들지 않는다", async () => {
  const controller = new AbortController(); controller.abort();
  const time = clock();
  const result = await runArrivingSeasons(inputs,
    {order: "parallel", concurrency: null}, async () => {
      assert.fail("취소된 실행의 시작");
    }, {signal: controller.signal, now: time.now, arrivalWait: time.wait});
  assert.ok(result.arrivals.every((a) => a.arrivedMs === null));
  assert.ok(result.seasons.every((s) => s.attempts.length === 0 &&
    s.status === "aborted"));
  assert.equal(time.pending(), 0);
});

test("TB09 타이머가 조금 일찍 깨어나도 남은 시간을 기다리고 접수한다", async () => {
  let now = 0;
  const waits: number[] = [];
  const result = await runArrivingSeasons([
    {id: "a", brandID: "A"}, {id: "b", brandID: "B"},
  ], {order: "parallel", concurrency: null}, async () =>
    ({status: "succeeded"}), {signal: new AbortController().signal,
    now: () => now, arrivalWait: async (ms) => {
      waits.push(ms); now += waits.length === 1 ? ms - 0.25 : ms;
    }});
  assert.deepEqual(waits, [100, 1]);
  assert.equal(result.arrivals[1].scheduledMs, 100);
  assert.equal(result.arrivals[1].arrivedMs, 100.75);
  assert.ok(result.seasons[1].attempts[0].startedMs >= 100);
});
