import assert from "node:assert/strict";
import test from "node:test";
import {QUEUE_POLICY} from "./contracts.js";
import {createQueuePipelineRuntime, runQueueBatchItems} from "./runtime.js";

test("PQ06 제품 runtime은 stage 상한과 재사용 예산을 사용한다", () => {
  const runtime = createQueuePipelineRuntime(new AbortController().signal);
  const resources = runtime.snapshot() as Record<string,
    {limit: number | null}>;
  assert.equal(resources.download?.limit, 4);
  assert.equal(resources.transform?.limit, 1);
  assert.equal(resources.upload?.limit, 4);
  assert.equal(resources.paths?.limit, null);
  assert.equal(runtime.sourceBuffers?.snapshot().budgetBytes,
    128 * 1024 * 1024);
  assert.equal(QUEUE_POLICY.seasonConcurrency, 6);
});

test("PQ06 취소는 신규 시즌 투입을 막고 이미 시작한 시즌의 종료를 기다린다", async () => {
  const controller = new AbortController();
  const started: number[] = [];
  let release: (() => void) | undefined;
  const draining = new Promise<void>((resolve) => {
    release = resolve;
  });
  const work = runQueueBatchItems(Array.from({length: 8}, (_, ordinal) =>
    ({ordinal, value: ordinal})), async (value) => {
    started.push(value);
    await draining;
    return value;
  }, {signal: controller.signal, concurrency: 3});
  await new Promise((resolve) => setTimeout(resolve, 0));
  controller.abort(new Error("drain"));
  if (!release) throw new Error("작업 대기 promise가 준비되지 않았습니다.");
  release();
  const results = await work;
  assert.deepEqual(started, [0, 1, 2]);
  assert.equal(results.filter((result) =>
    result.status === "completed").length, 3);
  assert.equal(results.filter((result) =>
    result.status === "notStarted").length, 5);
  assert.equal(results.some((result) => result.status === "failed"), false);
  await assert.rejects(() => runQueueBatchItems([], async () => 0, {
    signal: new AbortController().signal, concurrency: 7,
  }), /INVALID_QUEUE_BATCH_ITEMS/);
  await assert.rejects(() => runQueueBatchItems(Array.from({length: 81},
    (_, ordinal) => ({ordinal, value: ordinal})), async (value) => value, {
    signal: new AbortController().signal,
  }), /INVALID_QUEUE_BATCH_ITEMS/);
});
