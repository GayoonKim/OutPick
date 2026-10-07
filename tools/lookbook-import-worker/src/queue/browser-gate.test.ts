import assert from "node:assert/strict";
import test from "node:test";
import {BrowserImageGate} from "./browser-gate.js";

function deferred<T = void>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}

async function until(predicate: () => boolean): Promise<void> {
  for (let index = 0; index < 100; index++) {
    if (predicate()) return;
    await new Promise((resolve) => setImmediate(resolve));
  }
  throw new Error("GATE_STATE_TIMEOUT");
}

test("browser는 active image를 기다리고 대기 시작 뒤 image admission을 닫는다", async () => {
  const gate = new BrowserImageGate();
  const imageRelease = deferred();
  const browserRelease = deferred();
  const started: string[] = [];
  const image = gate.withImageWork(async () => {
    started.push("image-1");
    await imageRelease.promise;
  });
  await until(() => gate.snapshot().activeImages === 1);

  const browser = gate.withBrowserWork(async () => {
    started.push("browser");
    await browserRelease.promise;
  });
  await until(() => gate.snapshot().queuedBrowsers === 1);
  const nextImage = gate.withImageWork(async () => {
    started.push("image-2");
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(started, ["image-1"]);

  imageRelease.resolve();
  await until(() => gate.snapshot().activeBrowser);
  assert.deepEqual(started, ["image-1", "browser"]);
  browserRelease.resolve();
  await Promise.all([image, browser, nextImage]);
  assert.deepEqual(started, ["image-1", "browser", "image-2"]);
  assert.deepEqual(gate.snapshot(), {
    activeImages: 0, activeBrowser: false, queuedBrowsers: 0,
  });
});

test("대기 중 취소된 browser는 admission을 풀고 permit을 점유하지 않는다", async () => {
  const gate = new BrowserImageGate();
  const imageRelease = deferred();
  const controller = new AbortController();
  const image = gate.withImageWork(() => imageRelease.promise);
  await until(() => gate.snapshot().activeImages === 1);
  const browser = gate.withBrowserWork(
    async () => "unreachable", controller.signal,
  );
  await until(() => gate.snapshot().queuedBrowsers === 1);
  controller.abort(new Error("cancelled"));
  await assert.rejects(browser, /cancelled/);

  const secondImage = gate.withImageWork(async () => "started");
  assert.equal(await secondImage, "started");
  imageRelease.resolve();
  await image;
  assert.deepEqual(gate.snapshot(), {
    activeImages: 0, activeBrowser: false, queuedBrowsers: 0,
  });
});

test("여러 browser는 FIFO로 한 번에 하나씩 실행한다", async () => {
  const gate = new BrowserImageGate();
  const firstRelease = deferred();
  const order: number[] = [];
  let active = 0;
  let maxActive = 0;
  const first = gate.withBrowserWork(async () => {
    active++;
    maxActive = Math.max(maxActive, active);
    order.push(1);
    await firstRelease.promise;
    active--;
  });
  await until(() => gate.snapshot().activeBrowser);
  const second = gate.withBrowserWork(async () => {
    active++;
    maxActive = Math.max(maxActive, active);
    order.push(2);
    active--;
  });
  firstRelease.resolve();
  await Promise.all([first, second]);
  assert.deepEqual(order, [1, 2]);
  assert.equal(maxActive, 1);
});

test("browser 전환이 시작되기 전에 등록된 재사용 캐시를 비운다", async () => {
  const gate = new BrowserImageGate();
  let cleared = 0;
  const unregister = gate.registerBrowserTransitionCleanup(() => cleared++);
  try {
    await gate.withBrowserWork(async () => {
      assert.equal(gate.snapshot().activeBrowser, true);
      assert.equal(cleared, 1);
    });
    assert.equal(cleared, 1);
  } finally {
    unregister();
  }
  await gate.withBrowserWork(async () => undefined);
  assert.equal(cleared, 1);
});
