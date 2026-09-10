import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {writeFile, stat} from "node:fs/promises";
import test from "node:test";
import sharp from "sharp";
import type {Firestore} from "firebase-admin/firestore";
import type {Storage} from "firebase-admin/storage";
import {runCloudMediaJob} from "./cloudJob.js";

async function fixture(cancelDuringStore = false) {
  const bytes = await sharp({create: {width: 64, height: 64, channels: 3, background: "red"}}).jpeg().toBuffer();
  const sources = [0, 1, 2].map((index) => ({attachmentID: `a${index}`, path: `rooms/r/messages/u/a${index}/source`,
    generation: "7", sizeBytes: bytes.length, contentType: "image/jpeg",
    sha256: createHash("sha256").update(bytes).digest("hex")}));
  const data: Record<string, unknown> = {contractVersion: 2, processingStatus: "processing", leaseToken: "lease",
    roomID: "r", uploadID: "u", kind: "images", quarantineBucket: "quarantine", attachmentCount: 3,
    sourceManifest: sources, attachmentIDs: sources.map((x) => x.attachmentID), quarantinePaths: sources.map((x) => x.path)};
  const ref = {get: async () => ({exists: true, data: () => ({...data})}), set: async (value: object) => { Object.assign(data, value); }};
  const firestore = {doc: () => ref, runTransaction: async (body: (tx: unknown) => Promise<unknown>) => body({
    get: ref.get, update: (_ref: unknown, value: object) => Object.assign(data, value),
  })} as unknown as Firestore;
  const objects = new Map<string, {generation: string; size: number}>();
  let nextGeneration = 10;
  let active = 0;
  let peak = 0;
  let stores = 0;
  let deletingWhileStore = false;
  const downloaded: string[] = [];
  const storage = {bucket: () => ({
    file: (name: string, options?: {generation?: string}) => ({
      download: async ({destination}: {destination: string}) => {
        assert.equal(options?.generation, "7");
        downloaded.push(name);
        peak = Math.max(peak, ++active);
        await new Promise((resolve) => setTimeout(resolve, name.includes("a0") ? 10 : 1));
        await writeFile(destination, bytes);
        active--;
      },
      getMetadata: async () => {
        const existing = objects.get(name);
        if (!existing) throw Object.assign(new Error("missing"), {code: 404});
        return [existing];
      },
      delete: async ({ifGenerationMatch}: {ifGenerationMatch?: string}) => {
        deletingWhileStore ||= stores > 0;
        const existing = objects.get(name);
        if (existing && ifGenerationMatch && existing.generation !== ifGenerationMatch) throw Object.assign(new Error("stale"), {code: 412});
        objects.delete(name);
      },
    }),
    upload: async (localPath: string, options: {destination: string; preconditionOpts: {ifGenerationMatch: string | number}}) => {
      stores++;
      await new Promise((resolve) => setTimeout(resolve, 5));
      assert.equal(options.preconditionOpts.ifGenerationMatch, objects.get(options.destination)?.generation ?? 0);
      const metadata = {generation: String(nextGeneration++), size: (await stat(localPath)).size};
      objects.set(options.destination, metadata);
      if (cancelDuringStore) { data.processingStatus = "canceled"; data.leaseToken = null; }
      stores--;
      return [{metadata}];
    },
  })} as unknown as Storage;
  return {data, objects, downloaded, peak: () => peak, deletingWhileStore: () => deletingWhileStore,
    run: () => runCloudMediaJob({uploadPath: "Rooms/r/MediaUploads/u", leaseToken: "lease", kind: "images",
      readyBucket: "ready", imageConcurrency: 2}, {firestore, storage, nowMillis: Date.now})};
}

test("실제 이미지 변환을 포함한 worker는 source generation·사진 순서·동시성 2를 유지한다", async () => {
  const context = await fixture();
  await context.run();
  assert.equal(context.peak(), 2);
  assert.equal(context.objects.size, 6);
  assert.deepEqual((context.data.normalizedManifest as Array<{attachmentID: string}>).map((x) => x.attachmentID), ["a0", "a1", "a2"]);
});

test("저장 중 취소되면 모든 저장 종료 후 자신의 객체만 정리하고 완료를 기록하지 않는다", async () => {
  const context = await fixture(true);
  await assert.rejects(context.run());
  assert.equal(context.data.normalizedManifest, undefined);
  assert.equal(context.deletingWhileStore(), false);
  assert.equal(context.objects.size, 0);
  assert.equal(context.downloaded.length, 2);
});
