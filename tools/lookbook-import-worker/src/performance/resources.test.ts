import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import test from "node:test";
import {readContainerMemory, readContainerMemorySync} from "./resources.js";

test("메모리 표본 읽기는 포화된 libuv 작업 풀의 종료를 기다리지 않는다",
  async () => {
    const moduleURL = new URL("./resources.js", import.meta.url).href;
    const script = `
      import assert from 'node:assert/strict';
      import {pbkdf2} from 'node:crypto';
      import {readContainerMemory} from ${JSON.stringify(moduleURL)};
      let finished = false;
      const busy = new Promise((resolve, reject) => {
        pbkdf2('local-test', 'pool', 2000000, 32, 'sha256', error => {
          finished = true;
          if (error) reject(error); else resolve();
        });
      });
      await readContainerMemory();
      assert.equal(finished, false);
      await busy;
    `;
    await promisify(execFile)(process.execPath,
      ["--input-type=module", "-e", script],
      {env: {...process.env, UV_THREADPOOL_SIZE: "1"}, timeout: 10000});
  });

test("컨테이너 메모리는 cgroup 전체 사용량과 한도를 함께 읽는다", async () => {
  const result = await readContainerMemory(async (path) => {
    if (path.endsWith("memory.current")) return "1700\n";
    if (path.endsWith("memory.max")) return "2000\n";
    throw new Error("unexpected path");
  });
  assert.deepEqual(result,
    {source: "cgroup-v2", usedBytes: 1700, limitBytes: 2000});
});

test("컨테이너 메모리 미지원과 무제한은 사용량 0으로 대체하지 않는다", async () => {
  assert.equal(await readContainerMemory(async () => {
    throw new Error("unavailable");
  }), null);
  assert.equal(await readContainerMemory(async (path) =>
    path.endsWith(".current") ? "0" : "max"), null);
  assert.equal(await readContainerMemory(async () => ""), null);
});

test("cgroup v2가 없으면 유효한 v1 메모리 쌍을 사용한다", async () => {
  assert.deepEqual(await readContainerMemory(async (path) => {
    if (path.endsWith("usage_in_bytes")) return "100";
    if (path.endsWith("limit_in_bytes")) return "200";
    throw new Error("not v2");
  }), {source: "cgroup-v1", usedBytes: 100, limitBytes: 200});
});

test("작은 cgroup 메모리 파일은 동기 표본으로 읽고 환경 미지원은 null로 둔다", () => {
  assert.deepEqual(readContainerMemorySync((path) => {
    if (path.endsWith("memory.current")) return "850";
    if (path.endsWith("memory.max")) return "1000";
    throw new Error("unexpected path");
  }), {source: "cgroup-v2", usedBytes: 850, limitBytes: 1000});
  assert.deepEqual(readContainerMemorySync((path) => {
    if (path.endsWith("usage_in_bytes")) return "100";
    if (path.endsWith("limit_in_bytes")) return "200";
    throw new Error("not v2");
  }), {source: "cgroup-v1", usedBytes: 100, limitBytes: 200});
  assert.equal(readContainerMemorySync(() => "max"), null);
});
