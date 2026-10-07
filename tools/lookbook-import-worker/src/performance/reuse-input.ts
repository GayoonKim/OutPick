import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import type {Storage} from "firebase-admin/storage";
import {canonicalCandidateURL, resolveContentHashDedupe}
  from "../extraction/dedupe.js";
import {jpegBytes, uploadJPEG} from "../processor.js";
import {storeImageVariants} from "../pipeline/asset-pipeline.js";
import {inStage, type PipelineRuntime} from "../pipeline/resources.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {usingSourceBytes, withSourceBufferScope}
  from "../pipeline/source-buffer-store.js";
import type {ComparisonSeason} from "./comparison.js";
import {observeBuffer} from "./buffer-inventory.js";
import type {loadFrozenInput} from "./frozen-input.js";
import {measured, recordBytes} from "./metrics.js";
import type {ReuseTrace} from "./reuse-trace.js";

export type ConnectedInput =
  Awaited<ReturnType<typeof loadFrozenInput>>["connectedInput"];
export type ConnectedImage = ConnectedInput["covers"][number];
export type ConnectedTarget = ConnectedImage & {kind: string};
export type ConnectedIO = {
  readImage: (image: ConnectedImage, signal: AbortSignal) => Promise<Buffer>;
  upload: (item: ComparisonSeason, index: number, target: ConnectedTarget,
    variant: "thumb" | "detail", bytes: Buffer,
    signal: AbortSignal) => Promise<void>;
  savePaths: (item: ComparisonSeason, index: number,
    target: ConnectedTarget, signal: AbortSignal) => Promise<void>;
};
const hash = (bytes: Buffer) =>
  createHash("sha256").update(bytes).digest("hex");

// 품질 판정/검토 재개와 별개인 로컬 연결 경로다. HTTP 진입점은 없다.
export function connectedExecutor(input: ConnectedInput, trace?: ReuseTrace,
  prepareCover = false, io?: ConnectedIO) {
  return async (item: ComparisonSeason, pipeline: PipelineRuntime,
    signal: AbortSignal) => withSourceBufferScope(pipeline.sourceBuffers,
    async (scope) => {
      const season = input.seasons.find((s) => s.seasonID === item.seasonID);
      const expected = input.golden.find((s) => s.seasonID === item.seasonID);
      const cover = input.covers.find((s) => s.seasonID === item.seasonID);
      assert.ok(season && expected && cover);
      const download = (image: typeof cover) => measured("image.download",
        async () => {
          signal.throwIfAborted();
          const bytes = await (io ? io.readImage(image, signal) :
            input.readImage(image));
          recordBytes("image.download", "receivedBytes", bytes.length);
          return bytes;
        });
      const deduped = await resolveContentHashDedupe({pipeline,
        candidates: season.images,
        loadBytes: (image) => download({...image, seasonID: item.seasonID}),
        onHashedBytes: (image, bytes) => {
          if (Buffer.isBuffer(bytes)) {
            scope?.retain(canonicalCandidateURL(image.sourceURL),
              season.sourceURL, bytes);
          }
        }});
      assert.equal(deduped.complete, true);
      assert.equal(deduped.candidates.length, expected.uniqueImages);
      scope?.retainOnly(new Set(deduped.candidates.map((image) =>
        canonicalCandidateURL(image.sourceURL))), season.sourceURL);
      const targets = [...deduped.candidates.map((image) =>
        ({...image, seasonID: item.seasonID, kind: "post"})),
      {...cover, kind: "cover"}];
      let files = 0;
      let uploaded = 0;
      let paths = 0;
      const savedPaths = new Set<string>();
      const storage = {bucket: () => ({file: () => ({save: async () => {
        signal.throwIfAborted();
      }})})} as unknown as Storage;
      let prepared: Buffer | undefined;
      let releasePrepared: (() => void) | undefined;
      try {
        if (prepareCover) {
          const prepare = async () => {
            prepared = await inStage(pipeline, "download", () =>
              download(cover));
            releasePrepared = observeBuffer("source", prepared);
            signal.throwIfAborted();
            assert.equal(hash(prepared), cover.sha256);
          };
          if (trace) {
            await trace.prepare({season: item.seasonID,
              target: `cover-${targets.length - 1}`, kind: "cover"}, prepare);
          } else await prepare();
        }
        await mapScheduled(targets, pipeline.assets, (target, index) => {
          let loaded = false;
          const isPrepared = prepareCover && target.kind === "cover";
          const consume = async (bytes: Buffer) => {
            trace?.record({event: "source-ready",
              reused: !isPrepared && !loaded,
              ...(isPrepared ? {prepared: true} : {})});
            assert.equal(hash(bytes), target.sha256);
            let completedFiles = 0;
            await storeImageVariants(bytes, pipeline, {
              transform: async (source, variant) => {
                signal.throwIfAborted();
                const [maxPixel, quality] = target.kind === "cover" ?
                  variant === "thumb" ? [512, 75] : [1600, 88] :
                  variant === "thumb" ? [768, 82] : [1920, 90];
                const output = await jpegBytes(source, maxPixel, quality);
                const golden = expected.outputs.find((value) =>
                  value.kind === target.kind &&
                  value.sourceHash === target.sha256 &&
                  value.maxPixel === maxPixel);
                assert.ok(golden);
                assert.equal(hash(output), golden.sha256);
                assert.equal(output.length, golden.bytes);
                return output;
              },
              upload: async (bytes, variant) => {
                const path = `local-reuse/${item.id}/${index}/${variant}`;
                assert.ok(!savedPaths.has(path));
                if (io) {
                  await io.upload(item, index, target, variant, bytes, signal);
                } else await uploadJPEG(storage, path, bytes);
                savedPaths.add(path);
                files++;
                uploaded += bytes.length;
                completedFiles++;
              },
              savePaths: () => measured("paths.save", async () => {
                signal.throwIfAborted();
                assert.equal(completedFiles, 2);
                await io?.savePaths(item, index, target, signal);
                paths++;
              }),
            });
            assert.equal(hash(bytes), target.sha256);
          };
          const work = () => measured("asset", () => {
            if (isPrepared) {
              assert.ok(prepared);
              return consume(prepared);
            }
            return usingSourceBytes(scope,
              canonicalCandidateURL(target.sourceURL), season.sourceURL,
              () => {
                loaded = true;
                return inStage(pipeline, "download", () => download(target));
              }, consume);
          });
          return trace ? trace.target({season: item.seasonID,
            target: `${target.kind}-${index}`,
            kind: target.kind as "post" | "cover"}, work) : work();
        }, signal);
      } finally {
        releasePrepared?.();
        prepared = undefined;
      }
      assert.equal(files, expected.uploadFiles);
      assert.equal(savedPaths.size, expected.uploadFiles);
      assert.equal(uploaded, expected.uploadBytes);
      assert.equal(paths, expected.assetTargets);
      trace?.record({event: "season-end", season: item.seasonID});
      return {status: "succeeded" as const};
    });
}
