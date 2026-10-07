import assert from "node:assert/strict";
import test from "node:test";
import {QueueSupervisor} from "./supervisor.js";

function fixture(initialBytes = 100, limitBytes = 1000) {
  let current = 0;
  let usedBytes = initialBytes;
  const ticks: Array<() => void> = [];
  const deadlines: Array<() => void> = [];
  let cleared = 0;
  const supervisor = new QueueSupervisor({
    now: () => current,
    readMemory: () => ({source: "cgroup-v2", usedBytes,
      limitBytes}),
    timers: {
      every(callback) {
        ticks.push(callback);
        return () => {
          cleared++;
        };
      },
      after(callback) {
        deadlines.push(callback);
        return () => {
          cleared++;
        };
      },
    },
  });
  return {supervisor, ticks, deadlines, advance(ms: number) {
    current += ms;
    for (const tick of ticks) tick();
  }, setUsed(value: number) {
    usedBytes = value;
  },
  cleared: () => cleared};
}

test("PQ11 시작 표본이 85% 이상이면 시즌을 시작하기 전에 복구를 요구한다", () => {
  const state = fixture(850, 1000);
  assert.equal(state.supervisor.signal.aborted, true);
  assert.equal(state.supervisor.snapshot().memoryStop, "memory:startup-high");
  state.supervisor.stop();
  assert.equal(state.cleared(), 3);
});

test("PQ11 메모리 85%가 1초 지속되면 신규 시즌 투입을 중단한다", () => {
  const state = fixture(840, 1000);
  state.setUsed(850);
  for (let index = 0; index < 11; index++) state.advance(100);
  assert.equal(state.supervisor.signal.aborted, true);
  assert.equal(state.supervisor.snapshot().memoryStop,
    "memory:sustained-high");
});

test("PQ11 표본 공백 500ms 초과는 환경 검증 실패로 차단한다", () => {
  const state = fixture();
  state.advance(501);
  assert.equal(state.supervisor.signal.aborted, true);
  assert.equal(state.supervisor.snapshot().memoryStop,
    "environment:sample-gap");
});

test("PQ11 12분에 새 투입을 멈추고 14분 drain 목표 초과를 기록한다", () => {
  const state = fixture();
  state.deadlines[0]?.();
  assert.equal(state.supervisor.signal.aborted, true);
  assert.equal(state.supervisor.snapshot().admissionStop, "TIME_LIMIT");
  assert.equal(state.supervisor.snapshot().memoryStop, null);
  state.deadlines[1]?.();
  assert.equal(state.supervisor.snapshot().drainTargetExceeded, true);
});
