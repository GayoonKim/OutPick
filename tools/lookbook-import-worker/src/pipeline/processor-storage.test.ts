import assert from "node:assert/strict";
import {setImmediate} from "node:timers/promises";
import test from "node:test";
import sharp from "sharp";
import type {Firestore} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";
import {runSyncTargets} from "../processor.js";
import {PipelineRuntime} from "./resources.js";

const seasonPath = "brands/brand/seasons/season";
const postPath = `${seasonPath}/posts/post`;
const page = "https://brand.example/season";
const remoteURL = "https://brand.example/image.png";
const cover = {kind: "seasonCover" as const, brandID: "brand",
  seasonID: "season", remoteURL, sourcePageURL: page};
const post = {...cover, kind: "postImage" as const,
  postID: "post", mediaIndex: 0};

async function fixture(options: {
  signal?: AbortSignal;
  saveFile?: (path: string) => Promise<void>;
  saveDoc?: (path: string) => void;
} = {}) {
  const pipeline = new PipelineRuntime({
    signal: options.signal,
    assets: {kind: "refill", concurrency: 3},
    hashes: {kind: "refill", concurrency: 4},
    limits: {download: 2, transform: 2, upload: 2, paths: 1},
    sourceBufferBudgetBytes: 256 * 2**20,
  });
  assert.ok(pipeline.sourceBuffers);
  const scope = pipeline.sourceBuffers.openScope();
  const bytes = await sharp({create: {
    width: 24, height: 32, channels: 3, background: "#7e4a43",
  }}).png().toBuffer();
  scope.retain(remoteURL, page, bytes);
  const docs = new Map<string, Record<string, unknown>>([
    [seasonPath, {coverRemoteURL: remoteURL}],
    [postPath, {media: [{remoteURL, caption: "기존 속성"}],
      assetSyncStatus: "pending"}],
  ]);
  const writes: string[] = [];
  const uploads: string[] = [];
  const ref = (path: string): unknown => ({
    collection: (name: string) => ({doc: (id: string) =>
      ref(`${path}/${name}/${id}`)}),
    get: async () => ({data: () => docs.get(path)}),
    set: async (data: Record<string, unknown>, opts: {merge: boolean}) => {
      assert.equal(opts.merge, true);
      options.saveDoc?.(path);
      docs.set(path, {...docs.get(path), ...data});
      writes.push(path);
    },
  });
  const firestore = {
    collection: (name: string) => ({doc: (id: string) => ref(`${name}/${id}`)}),
  } as unknown as Firestore;
  const storage = {bucket: () => ({file: (path: string) => ({
    save: async (bytes: Buffer) => {
      assert.equal((await sharp(bytes).metadata()).format, "jpeg");
      await options.saveFile?.(path);
      uploads.push(path);
    },
  })})} as unknown as Storage;
  return {docs, writes, uploads, scope, pipeline,
    dependencies: {firestore, storage, assetSyncConcurrency: 3,
      pipeline, sourceBuffers: scope}};
}

test("실제 저장 중단은 진행 중 업로드를 회수하고 경로와 ready를 저장하지 않는다",
  async () => {
    const controller = new AbortController();
    let release!: () => void;
    let entered!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    const started = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const f = await fixture({signal: controller.signal, saveFile: async () => {
      entered();
      await pending;
    }});
    try {
      let ended = false;
      const work = runSyncTargets(f.dependencies, [post]).finally(() => {
        ended = true;
      });
      const rejected = assert.rejects(work,
        (error) => error === controller.signal.reason);
      await started;
      controller.abort();
      await setImmediate();
      assert.equal(ended, false);
      assert.equal(f.pipeline.snapshot().upload.active, 2);
      release();
      await rejected;
      assert.equal(f.uploads.length, 2);
      assert.equal(f.writes.length, 0);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "pending");
      assert.equal(f.pipeline.snapshot().upload.active, 0);
    } finally {
      release();
      f.scope.close();
    }
    assert.equal(f.pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
  });

test("실제 저장 함수는 두 JPEG와 기존 경로 계약을 기록하고 완료 항목은 건너뛴다",
  async () => {
    const f = await fixture();
    try {
      const result = await runSyncTargets(f.dependencies, [cover, post]);
      assert.ok(result.every((r) => r.succeeded && !r.skipped));
      assert.deepEqual([...f.uploads].sort(), [
        `${seasonPath}/cover.jpg`, `${seasonPath}/cover_thumb.jpg`,
        `${postPath}/detail.jpg`, `${postPath}/thumb.jpg`,
      ].sort());
      assert.equal(f.docs.get(seasonPath)?.coverPath,
        `${seasonPath}/cover.jpg`);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "ready");
      assert.deepEqual(f.docs.get(postPath)?.media, [{remoteURL,
        caption: "기존 속성", thumbPath: `${postPath}/thumb.jpg`,
        detailPath: `${postPath}/detail.jpg`}]);
      const retried = await runSyncTargets(f.dependencies, [cover, post]);
      assert.ok(retried.every((r) => r.succeeded && r.skipped));
      assert.equal(f.uploads.length, 4);
      assert.equal(f.writes.length, 2);
      assert.equal(f.pipeline.sourceBuffers?.snapshot().hits, 2);
    } finally {
      f.scope.close();
    }
    assert.equal(f.pipeline.sourceBuffers?.snapshot().retainedBytes, 0);
  });

test("실제 저장의 한 파일 실패는 ready를 막고 재시도에서 완료 대상을 제외한다",
  async () => {
    let fail = true;
    let release!: () => void;
    let entered!: () => void;
    const waiting = new Promise<void>((resolve) => {
      release = resolve;
    });
    const started = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const f = await fixture({saveFile: async (path) => {
      if (!fail) return;
      if (path === `${postPath}/thumb.jpg`) throw new Error("업로드 실패");
      if (path === `${postPath}/detail.jpg`) {
        entered();
        await waiting;
      }
    }});
    try {
      let ended = false;
      const work = runSyncTargets(f.dependencies, [cover, post])
        .then((result) => {
          ended = true;
          return result;
        });
      await started;
      await setImmediate();
      assert.equal(ended, false);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "pending");
      release();
      const result = await work;
      assert.equal(result[0].succeeded, true);
      assert.equal(result[1].succeeded, false);
      assert.equal(f.writes.includes(postPath), false);
      fail = false;
      const before = f.uploads.length;
      const retry = await runSyncTargets(f.dependencies, [cover, post]);
      assert.equal(retry[0].skipped, true);
      assert.equal(retry[1].succeeded, true);
      assert.equal(f.uploads.length - before, 2);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "ready");
    } finally {
      release();
      f.scope.close();
    }
  });

test("원본 재사용은 형제 종료를 보장하는 처리 경로를 요구한다", async () => {
  const f = await fixture();
  try {
    await assert.rejects(runSyncTargets(
      {...f.dependencies, pipeline: undefined}, [post]), /실험 경로/);
    assert.equal(f.uploads.length, 0);
  } finally {
    f.scope.close();
  }
});

test("실제 DB 쓰기 실패는 경로와 ready를 남기지 않고 다음 저장에서 복구한다",
  async () => {
    let fail = true;
    const f = await fixture({saveDoc: () => {
      if (fail) throw new Error("Firestore 실패");
    }});
    try {
      const [first] = await runSyncTargets(f.dependencies, [post]);
      assert.equal(first.succeeded, false);
      assert.equal(f.uploads.length, 2);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "pending");
      assert.deepEqual(f.docs.get(postPath)?.media,
        [{remoteURL, caption: "기존 속성"}]);
      fail = false;
      const [retry] = await runSyncTargets(f.dependencies, [post]);
      assert.equal(retry.succeeded, true);
      assert.equal(f.uploads.length, 4);
      assert.equal(f.docs.get(postPath)?.assetSyncStatus, "ready");
      for (const slots of Object.values(f.pipeline.snapshot())) {
        assert.equal(slots.active, 0);
        assert.equal(slots.queued, 0);
      }
    } finally {
      f.scope.close();
    }
  });
