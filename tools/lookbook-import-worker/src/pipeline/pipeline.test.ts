import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import {PipelineRuntime} from "./resources.js";
import {drainAll, mapScheduled, type LaunchPolicy} from "./scheduling.js";
import {storeImageVariants} from "./asset-pipeline.js";
import {resolveContentHashDedupe} from "../extraction/dedupe.js";
import {browserImageGate} from "../queue/browser-gate.js";
import {SourceBufferStore} from "./source-buffer-store.js";

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return {promise, resolve};
}
function runtime(limit: number | null = 2) {
  return new PipelineRuntime({
    assets: {kind: "refill", concurrency: null},
    hashes: {kind: "refill", concurrency: null},
    limits: {download: limit, transform: limit, upload: limit, paths: limit},
  });
}

test("중단된 묶음은 실행 중 형제를 기다리고 다음 이미지와 묶음을 시작하지 않는다",
  async () => {
    for (const kind of ["refill", "batch"] as const) {
      const controller = new AbortController();
      const release = deferred();
      const entered: number[] = [];
      let ended = false;
      const work = mapScheduled([0, 1, 2, 3],
        {kind, size: 3, concurrency: 2}, async (item) => {
          entered.push(item);
          await release.promise;
          return item;
        }, controller.signal).finally(() => {
        ended = true;
      });
      const rejected = assert.rejects(work,
        (error) => error === controller.signal.reason);
      await setImmediate();
      controller.abort();
      await setImmediate();
      assert.equal(ended, false);
      release.resolve();
      await rejected;
      assert.deepEqual(entered, [0, 1]);
    }
  });

test("공용 중단 신호는 대기 슬롯과 후속 단계를 막고 실행 중 permit을 유지한다",
  async () => {
    const controller = new AbortController();
    const shared = new PipelineRuntime({
      assets: {kind: "refill", concurrency: null},
      hashes: {kind: "refill", concurrency: null},
      limits: {download: 1, transform: 1, upload: 1, paths: 1},
      signal: controller.signal,
    });
    const release = deferred();
    const events: string[] = [];
    const work = storeImageVariants(Buffer.from("input"), shared, {
      transform: async (_bytes, variant) => {
        events.push(variant);
        await release.promise;
        return Buffer.from(variant);
      },
      upload: async () => assert.fail("취소 후 업로드 불가"),
      savePaths: async () => assert.fail("취소 후 경로 저장 불가"),
    });
    const rejected = assert.rejects(work,
      (error) => error === controller.signal.reason);
    await setImmediate();
    assert.equal(shared.snapshot().transform.queued, 1);
    controller.abort();
    await setImmediate();
    assert.equal(shared.snapshot().transform.queued, 0);
    assert.equal(shared.snapshot().transform.active, 1);
    release.resolve();
    await rejected;
    assert.deepEqual(events, ["thumb"]);
    assert.equal(shared.snapshot().transform.active, 0);
    await assert.rejects(shared.run("download", async () =>
      assert.fail("별도 신호가 공용 중단을 우회하면 안 된다"),
    new AbortController().signal));
  });

test("공용 슬롯은 여러 시즌의 합산 실행 수를 제한한다", async () => {
  const shared = runtime(2);
  const release = deferred();
  const entered: number[] = [];
  const jobs = [0, 1].map((job) => mapScheduled([0, 1, 2], shared.assets,
    (item) => shared.run("download", async () => {
      entered.push(job * 10 + item);
      await release.promise;
      return item;
    })));
  await setImmediate();
  assert.equal(entered.length, 2);
  assert.equal(shared.snapshot().download.queued, 4);
  release.resolve();
  await Promise.all(jobs);
  assert.equal(entered.length, 6);
  assert.equal(shared.snapshot().download.peakActive, 2);
  assert.equal(shared.snapshot().download.active, 0);
  assert.equal(shared.snapshot().download.queued, 0);
});

test("묶음은 느린 형제 작업까지 종료한 후 다음 묶음을 시작한다", async () => {
  const release = deferred();
  const entered: number[] = [];
  const work = mapScheduled([0, 1, 2, 3],
    {kind: "batch", size: 2, concurrency: 2}, async (item) => {
      entered.push(item);
      if (item === 1) await release.promise;
      return item;
    });
  await setImmediate();
  assert.deepEqual(entered, [0, 1]);
  release.resolve();
  assert.deepEqual(await work, [0, 1, 2, 3]);
});

test("묶음 실패도 형제 종료와 남은 결과 수집 이후에 전달한다", async () => {
  const release = deferred();
  const entered: number[] = [];
  const failure = new Error("첫 이미지 실패");
  const work = mapScheduled([0, 1, 2],
    {kind: "batch", size: 2, concurrency: null}, async (item) => {
      entered.push(item);
      if (item === 0) throw failure;
      if (item === 1) await release.promise;
      return item;
    });
  const rejection = assert.rejects(work, (error) => error === failure);
  await setImmediate();
  assert.deepEqual(entered, [0, 1]);
  release.resolve();
  await rejection;
  assert.deepEqual(entered, [0, 1, 2]);
});

test("기본 저장 경로는 두 출력과 경로 기록 순서를 유지한다", async () => {
  const events: string[] = [];
  await storeImageVariants(Buffer.from("input"), undefined, {
    transform: async (input, variant) => {
      assert.equal(input.toString(), "input");
      events.push(`transform-${variant}`);
      return Buffer.from(variant);
    },
    upload: async (bytes, variant) => {
      assert.equal(bytes.toString(), variant);
      events.push(`upload-${variant}`);
    },
    savePaths: async () => {
      events.push("paths");
    },
  });
  assert.deepEqual(events, ["transform-thumb", "transform-detail",
    "upload-thumb", "upload-detail", "paths"]);
});

test("빈자리 보충과 전체 제출은 입력 결과 순서를 유지한다", async () => {
  for (const concurrency of [2, null]) {
    const release = deferred();
    const entered: number[] = [];
    const work = mapScheduled([0, 1, 2], {kind: "refill", concurrency},
      async (item) => {
        entered.push(item);
        if (item === 0) await release.promise;
        return item;
      });
    await setImmediate();
    assert.deepEqual(entered, [0, 1, 2]);
    release.resolve();
    assert.deepEqual(await work, [0, 1, 2]);
  }
});

test("실패와 대기 취소 후 슬롯을 반환하고 실행 중 취소는 종료를 기다린다",
  async () => {
    const shared = runtime(1);
    const release = deferred();
    const activeAbort = new AbortController();
    const active = shared.run("upload", () => release.promise,
      activeAbort.signal);
    await setImmediate();
    const queuedAbort = new AbortController();
    const queued = shared.run("upload", async () => assert.fail("취소됨"),
      queuedAbort.signal);
    const rejected = assert.rejects(queued);
    queuedAbort.abort();
    await rejected;
    activeAbort.abort();
    assert.equal(shared.snapshot().upload.active, 1);
    assert.equal(shared.snapshot().upload.queued, 0);
    release.resolve();
    await active;
    await assert.rejects(shared.run("upload", async () => {
      throw new Error("업로드 실패");
    }));
    assert.equal(await shared.run("upload", async () => 42), 42);
    assert.equal(shared.snapshot().upload.active, 0);
  });

test("실험 실패는 형제 작업을 모두 회수한 뒤 원본 오류를 전달한다",
  async () => {
    const release = deferred();
    const failure = new Error("원본 실패");
    let ended = false;
    const work = drainAll([
      async () => {
        throw failure;
      },
      () => release.promise,
    ]);
    const rejection = assert.rejects(work, (error) => error === failure)
      .then(() => {
        ended = true;
      });
    await setImmediate();
    assert.equal(ended, false);
    release.resolve();
    await rejection;
  });

test("두 파일 성공 전에는 경로를 저장하지 않고 업로드 실패 형제를 기다린다",
  async () => {
    for (const fail of [false, true]) {
      const shared = runtime(2);
      const release = deferred();
      let paths = 0;
      let ended = false;
      const work = storeImageVariants(Buffer.from("image"), shared, {
        transform: async (bytes) => bytes,
        upload: async (_, variant) => {
          if (variant === "detail") await release.promise;
          if (fail && variant === "thumb") throw new Error("업로드 실패");
        },
        savePaths: async () => {
          paths++;
        },
      });
      const completion = (fail ? assert.rejects(work) : work)
        .then(() => {
          ended = true;
        });
      await setImmediate();
      assert.equal(paths, 0);
      assert.equal(ended, false);
      assert.equal(shared.snapshot().transform.active, 0);
      release.resolve();
      await completion;
      assert.equal(paths, fail ? 0 : 1);
      assert.equal(shared.snapshot().upload.active, 0);
    }
  });

test("변환 실패는 업로드를 막고 DB 실패는 재시도할 수 있게 슬롯을 반환한다",
  async () => {
    const shared = runtime(1);
    let uploads = 0;
    await assert.rejects(storeImageVariants(Buffer.from("x"), shared, {
      transform: async (_, variant) => {
        if (variant === "thumb") throw new Error("변환 실패");
        return Buffer.from("jpeg");
      },
      upload: async () => {
        uploads++;
      },
      savePaths: async () => assert.fail("변환 실패 뒤 저장 금지"),
    }));
    assert.equal(uploads, 0);
    const operations = {
      transform: async (bytes: Buffer) => bytes,
      upload: async () => {
        uploads++;
      },
      savePaths: async () => {
        throw new Error("DB 실패");
      },
    };
    await assert.rejects(storeImageVariants(
      Buffer.from("x"), shared, operations));
    await storeImageVariants(Buffer.from("x"), shared,
      {...operations, savePaths: async () => undefined});
    assert.equal(uploads, 4);
    for (const value of Object.values(shared.snapshot())) {
      assert.equal(value.active, 0);
      assert.equal(value.queued, 0);
    }
  });

test("해시 단계도 같은 다운로드 슬롯과 실패 후보 보존 계약을 사용한다",
  async () => {
    const shared = runtime(1);
    const release = deferred();
    const occupied = shared.run("download", () => release.promise);
    let loads = 0;
    const candidates = [0, 1, 2].map((i) => ({sourceURL: `https://x.test/${i}`}));
    const work = resolveContentHashDedupe({
      pipeline: shared, candidates,
      loadBytes: async (candidate) => {
        loads++;
        if (candidate === candidates[2]) throw new Error("다운로드 실패");
        return Buffer.from("same");
      },
    });
    await setImmediate();
    assert.equal(loads, 0);
    release.resolve();
    await occupied;
    const result = await work;
    assert.deepEqual(result.candidates, [candidates[0], candidates[2]]);
    assert.equal(result.failureCount, 1);
    assert.equal(result.complete, false);
    assert.equal(shared.snapshot().download.active, 0);
  });

test("콘텐츠 해시 다운로드는 Chromium 실행 중 시작하지 않는다", async () => {
  const release = deferred();
  const browser = browserImageGate.withBrowserWork(async () => release.promise);
  await setImmediate();
  let loads = 0;
  const work = resolveContentHashDedupe({
    candidates: [{sourceURL: "https://x.test/image.jpg"}],
    loadBytes: async () => {
      loads++;
      return Buffer.from("image-bytes");
    },
  });
  await setImmediate();
  assert.equal(browserImageGate.snapshot().activeBrowser, true);
  assert.equal(browserImageGate.snapshot().activeImages, 0);
  assert.equal(loads, 0);
  release.resolve();
  const [result] = await Promise.all([work, browser]);
  assert.equal(result.complete, true);
  assert.equal(loads, 1);
  assert.deepEqual(browserImageGate.snapshot(), {
    activeImages: 0, activeBrowser: false, queuedBrowsers: 0,
  });
});

test("browser 전환은 batch 원본 재사용 저장소의 보관 Buffer를 해제한다",
  async () => {
    const store = new SourceBufferStore(128);
    const scope = store.openScope();
    const source = Buffer.from("cached-original");
    scope.retain("https://x.test/image.jpg", "https://x.test/page", source);
    assert.equal(store.snapshot().retainedBytes, source.length);
    const unregister = browserImageGate.registerBrowserTransitionCleanup(() =>
      store.clearRetained());
    try {
      await browserImageGate.withBrowserWork(async () => {
        assert.equal(store.snapshot().retainedBytes, 0);
      });
    } finally {
      unregister();
      scope.close();
    }
    assert.equal(store.snapshot().retainedBytes, 0);
    assert.equal(store.snapshot().openScopes, 0);
  });

test("잘못된 슬롯과 실행 폭을 거절하고 null은 유한 입력 전체를 허용한다",
  async () => {
    for (const limit of [0, -1, 1.5, Infinity, NaN]) {
      assert.throws(() => runtime(limit));
      await assert.rejects(mapScheduled([1],
        {kind: "refill", concurrency: limit}, async (n) => n));
    }
    const invalid = {kind: "batch", size: 0, concurrency: 1} as LaunchPolicy;
    await assert.rejects(mapScheduled([], invalid, async () => 0));
    const shared = runtime(null);
    const release = deferred();
    const work = mapScheduled([1, 2, 3], shared.assets, () =>
      shared.run("upload", () => release.promise));
    await setImmediate();
    assert.equal(shared.snapshot().upload.active, 3);
    release.resolve();
    await work;
  });
