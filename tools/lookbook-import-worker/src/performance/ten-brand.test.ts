import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {runSeasons} from "./season-runner.js";
import {PipelineRuntime} from "../pipeline/resources.js";

// 제어 흐름 검사용 입력이며 유료 실험의 부하 manifest는 아니다.
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

test("TB01 열 브랜드의 시즌 여섯 제한과 해제는 직렬 정리 경계를 지킨다",
  async () => {
    for (const order of ["serial-brands", "parallel"] as const) {
      for (const concurrency of [6, null]) {
        const releases = inputs.map(() => deferred());
        const started = new Set<string>();
        const ended = new Set<string>();
        let active = 0; let peak = 0;
        const work = runSeasons(inputs, {order, concurrency}, async (item) => {
          const index = inputs.indexOf(item);
          if (order === "serial-brands") {
            assert.ok(inputs.filter((prior) =>
              prior.brandID < item.brandID).every((prior) =>
              ended.has(prior.id)));
          }
          started.add(item.id); active++; peak = Math.max(peak, active);
          await releases[index].promise;
          // 저장 이후 비동기 정리 완료까지 실행권을 유지한다.
          await setImmediate();
          ended.add(item.id); active--;
          return {status: "succeeded"};
        }, {signal: new AbortController().signal});
        try {
          await setImmediate();
          const expected = concurrency ??
            (order === "serial-brands" ? 8 : inputs.length);
          assert.equal(started.size, expected);
          releases[0].resolve();
          await setImmediate(); await setImmediate(); await setImmediate();
          if (concurrency === 6) {
            assert.ok(started.has("A-6"));
            assert.equal(started.has("B-0"), false);
            assert.equal(active, 6);
          }
          if (order === "serial-brands") {
            assert.ok([...started].every((id) => id.startsWith("A-")));
          }
        } finally {
          releases.forEach((release) => release.resolve());
          const result = await work;
          assert.ok(result.every((row) => row.status === "succeeded"));
        }
        assert.equal(ended.size, inputs.length);
        assert.equal(active, 0);
        assert.equal(peak, concurrency ??
          (order === "serial-brands" ? 8 : inputs.length));
      }
    }
  });

test("TB02 열 브랜드가 공유하는 단계 슬롯은 한도와 해제 및 반환을 지킨다",
  async () => {
    for (const stage of ["download", "transform", "upload", "paths"] as const) {
      for (const limit of [1, 4, null]) {
        const runtime = new PipelineRuntime({
          assets: {kind: "refill", concurrency: null},
          hashes: {kind: "refill", concurrency: null},
          limits: {download: 4, transform: 1, upload: 4, paths: null,
            [stage]: limit},
        });
        const release = deferred();
        let active = 0; let peak = 0; let complete = 0;
        const work = Promise.all(inputs.map(() => runtime.run(stage,
          async () => {
            active++; peak = Math.max(peak, active);
            await release.promise;
            active--; complete++;
          })));
        try {
          await setImmediate();
          assert.equal(active, limit ?? inputs.length);
        } finally {
          release.resolve(); await work;
        }
        assert.equal(peak, limit ?? inputs.length);
        assert.equal(complete, inputs.length);
        assert.equal(runtime.snapshot()[stage].active, 0);
        assert.equal(runtime.snapshot()[stage].queued, 0);
      }
    }
  });
