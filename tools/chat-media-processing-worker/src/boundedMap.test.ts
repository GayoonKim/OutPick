import assert from "node:assert/strict";
import test from "node:test";
import {boundedMap, imageConcurrency} from "./boundedMap.js";

test("사진 동시성 상한과 선택 순서를 유지한다", async () => {
  let active = 0;
  let peak = 0;
  const result = await boundedMap([0, 1, 2, 3, 4], 2, async (value) => {
    peak = Math.max(peak, ++active);
    await new Promise((resolve) => setTimeout(resolve, value === 0 ? 15 : 1));
    active--;
    return value;
  });
  assert.equal(peak, 2);
  assert.deepEqual(result, [0, 1, 2, 3, 4]);
});

test("첫 오류 뒤 신규 작업을 중단하고 진행 중 저장 종료를 기다린다", async () => {
  const started: number[] = [];
  let finished = false;
  const failure = new Error("failed");
  await assert.rejects(boundedMap([0, 1, 2, 3], 2, async (value) => {
    started.push(value);
    if (value === 0) throw failure;
    await new Promise((resolve) => setTimeout(resolve, 10));
    finished = true;
  }), failure);
  assert.deepEqual(started, [0, 1]);
  assert.equal(finished, true);
});

test("측정 전 기본값 1과 명시적 비교값만 허용한다", () => {
  assert.equal(imageConcurrency(undefined), 1);
  assert.equal(imageConcurrency("4"), 4);
  for (const value of ["0", "5", "NaN", "1.5"]) assert.throws(() => imageConcurrency(value));
});
