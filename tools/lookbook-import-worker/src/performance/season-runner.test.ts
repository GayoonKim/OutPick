import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {runSeasons} from "./season-runner.js";

const inputs = [{id: "a1", brandID: "a"}, {id: "a2", brandID: "a"},
  {id: "b1", brandID: "b"}, {id: "b2", brandID: "b"}];
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}
const options = () => ({signal: new AbortController().signal});

test("브랜드 순차는 다른 브랜드와 병렬이며 검토 대기 뒤 다음 시즌을 시작한다",
  async () => {
    const release = deferred();
    const events: string[] = [];
    const work = runSeasons(inputs,
      {order: "serial-per-brand", concurrency: null}, async ({id}) => {
        events.push(id);
        if (id === "a1") await release.promise;
        return {status: "needs-review"};
      }, options());
    await setImmediate();
    assert.deepEqual(events, ["a1", "b1", "b2"]);
    release.resolve();
    const results = await work;
    assert.deepEqual(events, ["a1", "b1", "b2", "a2"]);
    assert.deepEqual(results.map((item) => item.id), inputs.map((x) => x.id));
    assert.ok(results.every((item) => item.status === "needs-review" &&
      item.attempts.length === 1));
  });

test("시즌 병렬과 실행 폭은 입력 순서 보존과 별개로 적용한다", async () => {
  for (const concurrency of [2, null]) {
    const release = deferred();
    const entered: string[] = [];
    const work = runSeasons(inputs, {order: "parallel", concurrency},
      async ({id}) => {
        entered.push(id);
        await release.promise;
        return {status: "succeeded"};
      }, options());
    await setImmediate();
    assert.deepEqual(entered,
      inputs.slice(0, concurrency ?? 4).map((x) => x.id));
    release.resolve();
    assert.ok((await work).every((item) => item.status === "succeeded"));
  }
});

test("시즌 재시도는 최초 포함 다섯 번이며 대기 중 브랜드 순서를 유지한다",
  async () => {
    const release = deferred();
    const events: string[] = [];
    let waits = 0;
    const work = runSeasons(inputs,
      {order: "serial-per-brand", concurrency: null}, async ({id}, context) => {
        events.push(`${id}-${context.attempt}`);
        return id === "a1" ? {status: "retryable", retryAfterMs: 123} :
          {status: "succeeded"};
      }, {...options(), wait: async (ms) => {
        assert.equal(ms, 123);
        waits++;
        await release.promise;
      }});
    await setImmediate();
    assert.deepEqual(events, ["a1-1", "b1-1", "b2-1"]);
    release.resolve();
    const results = await work;
    assert.equal(waits, 4);
    assert.equal(results[0].status, "failed");
    assert.deepEqual(results[0].attempts.map((entry) => entry.number),
      [1, 2, 3, 4, 5]);
    assert.equal(events.at(-1), "a2-1");
  });

test("최종 실패와 실행 예외는 재시도를 만들지 않고 다음 시즌을 허용한다",
  async () => {
    const results = await runSeasons(inputs,
      {order: "serial-per-brand", concurrency: null}, async ({id}) => {
        if (id === "a1") throw new Error("실패");
        return {status: id === "b1" ? "failed" : "succeeded"};
      }, options());
    assert.deepEqual(results.map((x) => x.status),
      ["failed", "succeeded", "failed", "succeeded"]);
    assert.ok(results.every((x) => x.attempts.length === 1));
    assert.equal(results[0].attempts[0].status, "operation-error");
  });

test("시즌 중단은 신규 시도를 막고 실행 중 형제와 미시작 결과를 보존한다",
  async () => {
    const controller = new AbortController();
    const release = deferred();
    let ended = false;
    const work = runSeasons(inputs,
      {order: "serial-per-brand", concurrency: null}, async () => {
        await release.promise;
        return {status: "succeeded"};
      }, {signal: controller.signal}).then((value) => {
      ended = true;
      return value;
    });
    await setImmediate();
    controller.abort();
    await setImmediate();
    assert.equal(ended, false);
    release.resolve();
    const results = await work;
    assert.deepEqual(results.map((x) => x.attempts.length), [1, 0, 1, 0]);
    assert.ok(results.every((x) => x.status === "aborted"));
    assert.equal(results[0].attempts[0].status, "succeeded");
    assert.equal(results[0].attempts[0].endedMs >=
      results[0].attempts[0].startedMs, true);
  });

test("재시도 대기 취소와 시작 전 취소는 추가 시도 횟수를 소비하지 않는다",
  async () => {
    const controller = new AbortController();
    const work = runSeasons(inputs,
      {order: "serial-per-brand", concurrency: 1}, async () =>
        ({status: "retryable", retryAfterMs: 60000}),
      {signal: controller.signal});
    await setImmediate();
    controller.abort();
    assert.deepEqual((await work).map((x) => x.attempts.length), [1, 0, 0, 0]);
    const results = await runSeasons(inputs,
      {order: "parallel", concurrency: null}, async () => {
        assert.fail("시작 전 취소는 실행하지 않는다");
      }, {signal: controller.signal});
    assert.ok(results.every((x) => x.attempts.length === 0));
  });

test("잘못된 시즌 입력과 중복 ID는 실행 전에 차단한다", async () => {
  for (const items of [[], [inputs[0], inputs[0]], [{id: "a", brandID: ""}]]) {
    await assert.rejects(runSeasons(items,
      {order: "parallel", concurrency: null}, async () => {
        assert.fail("입력 오류에서 실행하면 안 된다");
      }, options()));
  }
  const results = await runSeasons(inputs,
    {order: "parallel", concurrency: null}, async () =>
      ({status: "retryable", retryAfterMs: -1}), options());
  assert.ok(results.every((x) => x.status === "failed" &&
    x.attempts[0].status === "operation-error"));
});
