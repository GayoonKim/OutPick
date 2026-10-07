import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {resolve, sep} from "node:path";
import type {Storage} from "firebase-admin/storage";
import {extractImageCandidates} from "../extraction/image-candidates.js";
import {collectExpectedCountEvidence} from "../extraction/expected-count.js";
import {detectProgrammaticGallery} from "../extraction/programmatic-gallery.js";
import {evaluateExtractionQuality} from "../extraction/quality.js";
import {resolveContentHashDedupe} from "../extraction/dedupe.js";
import {fallbackReasonForExtraction, jpegBytes, uploadJPEG}
  from "../processor.js";
import {inStage} from "../pipeline/resources.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {storeImageVariants} from "../pipeline/asset-pipeline.js";
import {measured, recordBytes} from "./metrics.js";
import type {runComparison} from "./comparison.js";

type Image = {sourceURL: string; path: string; sha256: string; bytes: number};
type Season = {seasonID: string; sourceURL: string; htmlSha256: string;
  images: Image[]};
type Golden = {seasonID: string; uniqueImages: number; uploadFiles: number;
  uploadBytes: number; assetTargets: number;
  outputs: Array<{kind: string; sourceHash: string; maxPixel: number;
    sha256: string; bytes: number}>};
const hash = (bytes: string | Buffer) =>
  createHash("sha256").update(bytes).digest("hex");

export async function loadFrozenInput(directory: string) {
  const root = resolve(directory);
  function localPath(path: string): string {
    const resolved = resolve(root, path);
    assert.ok(resolved.startsWith(`${root}${sep}`));
    return resolved;
  }
  const manifest = JSON.parse(await readFile(localPath("manifest.json"),
    "utf8")) as {inputDigest: string; seasons: Season[]; errors: unknown[]};
  const {covers} = JSON.parse(await readFile(
    localPath("covers.json"), "utf8")) as
    {covers: Array<Image & {seasonID: string}>};
  const goldenBytes = await readFile(localPath("input-validation.json"));
  const golden = JSON.parse(goldenBytes.toString()) as {
    verdict: string; seasons: Golden[]};
  assert.equal(manifest.errors.length, 0);
  assert.equal(golden.verdict, "passed");
  assert.equal(manifest.seasons.length, 6);
  assert.equal(covers.length, 6);
  assert.equal(golden.seasons.length, 6);
  const digest = hash(JSON.stringify(manifest.seasons.map((season) => ({
    seasonID: season.seasonID, html: season.htmlSha256,
    images: season.images.map((image, index) =>
      ({order: index + 1, sha256: image.sha256})),
  }))));
  assert.equal(digest, manifest.inputDigest);
  const inputDigest = hash(JSON.stringify({manifest: manifest.inputDigest,
    covers: covers.map((cover) => cover.sha256), golden: hash(goldenBytes)}));
  const readImage = async (image: Image) => {
    const bytes = await readFile(localPath(image.path));
    assert.equal(bytes.length, image.bytes);
    assert.equal(hash(bytes), image.sha256);
    return bytes;
  };
  // 사전 무결성 검사는 측정 밖에서 수행하고 원본 전체를 메모리에 보관하지 않는다.
  for (const season of manifest.seasons) {
    const html = await readFile(localPath(`html/${season.seasonID}.html`));
    assert.equal(hash(html), season.htmlSha256);
    assert.deepEqual(extractImageCandidates(html.toString(), season.sourceURL)
      .candidates.map((image) => image.sourceURL),
    season.images.map((image) => image.sourceURL));
    for (const image of season.images) await readImage(image);
  }
  for (const cover of covers) await readImage(cover);

  const execute: Parameters<typeof runComparison>[1] =
    async (phase, item, {pipeline, signal}) => {
      const season = manifest.seasons.find((s) => s.seasonID === item.seasonID);
      const expected = golden.seasons.find((s) => s.seasonID === item.seasonID);
      const cover = covers.find((s) => s.seasonID === item.seasonID);
      assert.ok(season && expected && cover);
      const pending = new Set<Promise<unknown>>();
      const tracked = <T>(operation: () => Promise<T>): Promise<T> => {
        const work = operation();
        pending.add(work);
        void work.then(() => pending.delete(work), () => pending.delete(work));
        return work;
      };
      const download = (image: Image) => measured("image.download",
        async () => {
          signal.throwIfAborted();
          const bytes = await readFile(localPath(image.path));
          recordBytes("image.download", "receivedBytes", bytes.length);
          return bytes;
        });
      try {
        if (phase === "local-extraction") {
          const html = await measured("html.download", async () => {
            const bytes = await readFile(localPath(
              `html/${season.seasonID}.html`));
            recordBytes("html.download", "receivedBytes", bytes.length);
            return bytes.toString();
          });
          const extraction = extractImageCandidates(html, season.sourceURL);
          const gallery = detectProgrammaticGallery(html);
          assert.equal(fallbackReasonForExtraction(extraction, html, gallery),
            null);
          assert.deepEqual(extraction.candidates.map((x) => x.sourceURL),
            season.images.map((x) => x.sourceURL));
          const deduped = await resolveContentHashDedupe({pipeline,
            candidates: season.images, loadBytes: download});
          assert.equal(deduped.complete, true);
          assert.equal(deduped.candidates.length, expected.uniqueImages);
          const quality = evaluateExtractionQuality({
            candidateCount: deduped.candidates.length,
            rawCandidateCount: extraction.rawCandidateCount,
            staticCandidateCount: extraction.candidates.length,
            renderedCandidateCount: null,
            expectedCountEvidence: collectExpectedCountEvidence(html,
              season.sourceURL, extraction.candidates.length),
            programmaticGalleryDetected: gallery.detected,
            contentHashComplete: deduped.complete,
          });
          assert.deepEqual(quality, {status: "needsReview",
            reasons: ["expected_count_unverified"]});
          return {status: "needs-review"};
        }
        // 승인 후 저장 입력은 고정된 golden에서 독립 구성한다. review를 승인하지 않는다.
        const seen = new Set<string>();
        const unique = season.images.filter((image) => {
          if (seen.has(image.sha256)) return false;
          seen.add(image.sha256);
          return true;
        });
        const targets = [...unique.map((image) => ({...image, kind: "post"})),
          {...cover, kind: "cover"}];
        let files = 0;
        let uploaded = 0;
        let paths = 0;
        const storage = {bucket: () => ({file: () => ({save: async () => {
          signal.throwIfAborted();
        }})})} as unknown as Storage;
        await mapScheduled(targets,
          pipeline?.assets ?? {kind: "refill", concurrency: 3},
          (target) => measured("asset", async () => {
            const input = await inStage(pipeline, "download", () =>
              download(target));
            let completedFiles = 0;
            await storeImageVariants(input, pipeline, {
              transform: (bytes, variant) => tracked(async () => {
                signal.throwIfAborted();
                const [maxPixel, quality] = target.kind === "cover" ?
                  variant === "thumb" ? [512, 75] : [1600, 88] :
                  variant === "thumb" ? [768, 82] : [1920, 90];
                const output = await jpegBytes(bytes, maxPixel, quality);
                const match = expected.outputs.find((value) =>
                  value.kind === target.kind &&
                  value.sourceHash === target.sha256 &&
                  value.maxPixel === maxPixel);
                assert.ok(match);
                assert.equal(hash(output), match.sha256);
                assert.equal(output.length, match.bytes);
                return output;
              }),
              upload: (bytes, variant) => tracked(async () => {
                await uploadJPEG(storage,
                  `local-spy/${item.id}/${variant}`, bytes);
                files++;
                uploaded += bytes.length;
                completedFiles++;
              }),
              savePaths: () => measured("paths.save", async () => {
                signal.throwIfAborted();
                assert.equal(completedFiles, 2);
                paths++;
              }),
            });
          }), signal);
        assert.equal(files, expected.uploadFiles);
        assert.equal(uploaded, expected.uploadBytes);
        assert.equal(paths, expected.assetTargets);
        return {status: "succeeded"};
      } finally {
        // 기존 A의 Promise.all 조기 실패에서 남은 sharp/업로드도 회수한다.
        while (pending.size) await Promise.allSettled([...pending]);
      }
    };
  return {inputDigest, execute,
    connectedInput: {seasons: manifest.seasons, covers,
      golden: golden.seasons, readImage}};
}
