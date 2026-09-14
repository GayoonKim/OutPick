import assert from "node:assert/strict";
import test from "node:test";
import {boundedMap} from "../../src/media/boundedMap.js";

test("전체 실행은 고정60 상한 없이 입력 크기를 따르고 입력 순서를 보존한다", async () => {
  const items = Array.from({length: 73}, (_, i) => i);
  const releases = [];
  const pending = boundedMap(items, items.length, i => new Promise(resolve => { releases[i] = resolve; }));
  assert.equal(releases.length, 73);
  releases.toReversed().forEach((resolve, i) => resolve(72 - i));
  assert.deepEqual(await pending, items);
});

test("빈 전체 대상은 작업을 실행하지 않는다", async () => {
  assert.deepEqual(await boundedMap([], 1, () => assert.fail("빈 작업 호출 금지")), []);
});
