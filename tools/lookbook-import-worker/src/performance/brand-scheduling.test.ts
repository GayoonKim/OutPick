import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {runSeasons} from "./season-runner.js";
import {PipelineRuntime} from "../pipeline/resources.js";
import {storeImageVariants} from "../pipeline/asset-pipeline.js";
import {withSourceBufferScope} from "../pipeline/source-buffer-store.js";

const inputs = [{id: "a1", brandID: "a"}, {id: "a2", brandID: "a"},
  {id: "b1", brandID: "b"}, {id: "b2", brandID: "b"}];
const policy = {order: "serial-brands" as const, concurrency: 2};
const options = () => ({signal: new AbortController().signal});
function latch() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}

test("BF01 브랜드 FIFO는 비연속 입력을 묶고 내부 시즌만 병렬로 시작한다", async () => {
  const gate = latch();
  const entered: string[] = [];
  const shuffled = [inputs[0], inputs[2], inputs[1], inputs[3]];
  const work = runSeasons(shuffled, policy, async ({id}) => {
    entered.push(id);
    if (id.startsWith("a")) await gate.promise;
    return {status: "succeeded"};
  }, options());
  await setImmediate();
  assert.deepEqual(entered, ["a1", "a2"]);
  gate.resolve();
  assert.deepEqual((await work).map((r) => r.id), shuffled.map((s) => s.id));
  assert.deepEqual(entered, ["a1", "a2", "b1", "b2"]);
});

test("BF02 브랜드 전환은 두 업로드 경로 저장과 원본 정리까지 기다린다", async () => {
  const upload = latch();
  const paths = latch();
  const entered: string[] = [];
  const pipeline = new PipelineRuntime({
    assets: {kind: "refill", concurrency: 4},
    hashes: {kind: "refill", concurrency: 4},
    limits: {download: 4, transform: 1, upload: 4, paths: null},
    sourceBufferBudgetBytes: 128});
  const uploads = new Map<string, number>();
  let saved = 0;
  const work = runSeasons(inputs, policy, async ({id}) => {
    if (id === "b1") {
      assert.equal(saved, 2);
      assert.equal(pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
      assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 0);
    }
    entered.push(id);
    await withSourceBufferScope(pipeline.sourceBuffers, async (scope) => {
      const source = Buffer.alloc(4);
      scope?.retain(id, id, source);
      await storeImageVariants(source, pipeline, {
        transform: async () => Buffer.from("jpeg"),
        upload: async () => {
          if (id.startsWith("a")) {
            await upload.promise;
            uploads.set(id, (uploads.get(id) ?? 0) + 1);
          }
        },
        savePaths: async () => {
          if (id.startsWith("a")) {
            assert.equal(uploads.get(id), 2);
            await paths.promise; saved++;
          }
        },
      });
    });
    return {status: "succeeded"};
  }, options());
  await setImmediate();
  assert.deepEqual(entered, ["a1", "a2"]);
  upload.resolve();
  await setImmediate();
  assert.deepEqual(entered, ["a1", "a2"]);
  assert.equal(pipeline.sourceBuffers?.snapshot().openScopes, 2);
  paths.resolve();
  assert.ok((await work).every((r) => r.status === "succeeded"));
  assert.ok(Object.values(pipeline.snapshot())
    .every((s) => !s.active && !s.queued));
});

test("BF03 검토 대기와 실패는 형제 정리 후 다음 브랜드를 허용한다", async () => {
  const gate = latch();
  const entered: string[] = [];
  const work = runSeasons(inputs, policy, async ({id}) => {
    entered.push(id);
    if (id === "a1") return {status: "needs-review"};
    if (id === "a2") {
      await gate.promise; return {status: "failed"};
    }
    return {status: "succeeded"};
  }, options());
  await setImmediate();
  assert.deepEqual(entered, ["a1", "a2"]);
  gate.resolve();
  assert.deepEqual((await work).map((r) => r.status),
    ["needs-review", "failed", "succeeded", "succeeded"]);
});

test("BF04 브랜드 차례와 총 다섯 시도는 재시도 대기 중 유지된다", async () => {
  const gate = latch();
  const entered: string[] = [];
  let waits = 0;
  const work = runSeasons(inputs, policy, async ({id}, {attempt}) => {
    entered.push(`${id}:${attempt}`);
    return id === "a1" ? {status: "retryable", retryAfterMs: 10} :
      {status: "succeeded"};
  }, {...options(), wait: async () => {
    waits++; await gate.promise;
  }});
  await setImmediate();
  assert.deepEqual(entered, ["a1:1", "a2:1"]);
  gate.resolve();
  const result = await work;
  assert.equal(waits, 4);
  assert.equal(result[0].status, "failed");
  assert.equal(result[0].attempts.length, 5);
  assert.equal(result[2].attempts.length, 1);
  assert.ok(entered.indexOf("b1:1") > entered.indexOf("a1:5"));
});

test("BF05 브랜드 취소는 다음 브랜드를 막고 시작한 형제를 회수한다", async () => {
  const controller = new AbortController();
  const gate = latch();
  let done = false;
  let active = 0;
  const work = runSeasons(inputs, policy, async () => {
    active++;
    try {
      await gate.promise; return {status: "succeeded"};
    } finally {
      active--;
    }
  }, {signal: controller.signal}).then((r) => {
    done = true; return r;
  });
  await setImmediate();
  controller.abort(new Error("memory"));
  await setImmediate();
  assert.equal(done, false);
  assert.equal(active, 2);
  gate.resolve();
  assert.deepEqual((await work).map((r) => r.attempts.length), [1, 1, 0, 0]);
  assert.equal(active, 0);
});

test("BF06 한 브랜드의 병렬 폭은 브랜드 순차 도입 전후 동일하다", async () => {
  for (const order of ["parallel", "serial-brands"] as const) {
    const gate = latch();
    const entered: string[] = [];
    const own = inputs.map((i) => ({...i, brandID: "one"}));
    const work = runSeasons(own, {order, concurrency: 2}, async ({id}) => {
      entered.push(id); await gate.promise; return {status: "succeeded"};
    }, options());
    await setImmediate();
    assert.deepEqual(entered, ["a1", "a2"]);
    gate.resolve();
    assert.ok((await work).every((r) => r.status === "succeeded"));
  }
});
