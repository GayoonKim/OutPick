import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import sharp from "sharp";
import {jpegBytes} from "../processor.js";
import {mapScheduled} from "../pipeline/scheduling.js";
import {comparisonInputs} from "./comparison.js";
import {deriveLargeInput, largeTraceProfile} from "./large-input.js";
import {runReuse, type ReusePlan} from "./reuse-comparison.js";
import {contractFor, inspectContractTrace, PRESSURE_INPUT}
  from "./reuse-contract.js";
import {ReuseTrace} from "./reuse-trace.js";

export const brandTestMemory = {maxSampleGapMs: 500, readMemory: async () =>
  ({source: "cgroup-v2" as const, usedBytes: 1, limitBytes: 2 * 2**30})};
export async function brandMetadata() {
  const input = JSON.parse(await readFile(new URL(
    "../../fixtures/performance-large-base.json", import.meta.url), "utf8"));
  return {...input, readImage: async () => {
    assert.fail("메타데이터 fixture에서 원본 파일을 읽으면 안 된다");
  }};
}

// 집계 계약용 합성 사건이다. 실측 시간/원본 이미지 처리의 증거가 아니다.
export async function fakeBrandPayload(plan: ReusePlan) {
  const base = await brandMetadata();
  const contract = plan.largeInput ?
    deriveLargeInput(base, PRESSURE_INPUT).contract :
    contractFor(base, "synthetic-three");
  const profile = plan.largeInput ? largeTraceProfile(contract) : undefined;
  const trace = new ReuseTrace(profile);
  const value = await runReuse(plan, async (season, pipeline) => {
    const own = contract.find((s) => s.seasonID === season.id)!;
    const cover = own.targets.at(-1)!;
    await trace.prepare({season: season.id, target: cover.id, kind: "cover"},
      () => pipeline.run("download", async () => undefined));
    await mapScheduled(own.targets, pipeline.assets, (target) =>
      trace.target({season: season.id, target: target.id, kind: target.kind},
        async () => {
          const prepared = target.kind === "cover";
          const reused = !prepared &&
          (!plan.largeInput || target.id === "post-0");
          if (!prepared && !reused) {
            await pipeline.run("download", async () => undefined);
          }
          trace.record({event: "source-ready", reused,
            ...(prepared ? {prepared: true} : {})});
          await Promise.all([0, 1].map(() =>
            pipeline.run("transform", async () => undefined)));
          await Promise.all([0, 1].map(() =>
            pipeline.run("upload", async () => undefined)));
          await pipeline.run("paths", async () => undefined);
        }));
    trace.record({event: "season-end", season: season.id});
    return {status: "succeeded"};
  }, brandTestMemory, trace);
  const counts = inspectContractTrace(contract, trace.snapshot(), profile);
  const stages = (value.results[0].reports[0] as {measurement: {stages:
    Record<string, Record<string, number>>}}).measurement.stages;
  for (const [name, count] of Object.entries({"image.download": counts.reads,
    "image.hash": counts.hashReads, "image.transform": counts.files,
    "file.upload": counts.files, "paths.save": counts.trace.assets})) {
    Object.assign(stages[name],
      {started: count, succeeded: count, peakActive: 1});
  }
  stages["image.download"].receivedBytes = counts.readBytes;
  stages["file.upload"].completedBytes = counts.uploadBytes;
  value.cache = {budgetBytes: 128 * 2**20, retainedBytes: 0, openScopes: 0,
    hits: counts.trace.reused, misses: counts.posts - counts.trace.reused,
    rejectedByBudget: counts.posts - counts.trace.reused,
    peakRetainedBytes: counts.minimumPeakBytes};
  return {...value, inputContract: contract};
}

export async function tinyBrandInput() {
  const bytes = await sharp({create: {width: 8, height: 8, channels: 3,
    background: {r: 30, g: 90, b: 120}}}).png().toBuffer();
  const hash = (b: Buffer) => createHash("sha256").update(b).digest("hex");
  const image = {sourceURL: "https://example.com/post.png", path: "unused",
    sha256: hash(bytes), bytes: bytes.length};
  const outputs: {kind: "post" | "cover"; maxPixel: number;
    sourceHash: string; sha256: string; bytes: number}[] = [];
  for (const [kind, maxPixel, quality] of [
    ["post", 768, 82], ["post", 1920, 90],
    ["cover", 512, 75], ["cover", 1600, 88]] as const) {
    const jpeg = await jpegBytes(bytes, maxPixel, quality);
    outputs.push({kind, maxPixel, sourceHash: image.sha256,
      sha256: hash(jpeg), bytes: jpeg.length});
  }
  const ids = comparisonInputs("six").map((s) => s.id);
  let reads = 0;
  const input = {seasons: ids.map((seasonID) => ({seasonID,
    sourceURL: `https://example.com/${seasonID}`, htmlSha256: "0".repeat(64),
    images: [image, {...image,
      sourceURL: "https://example.com/duplicate.png"}]})),
  covers: ids.map((seasonID) => ({...image, seasonID,
    sourceURL: "https://example.com/cover.png"})),
  golden: ids.map((seasonID) => ({seasonID, uniqueImages: 1, uploadFiles: 4,
    uploadBytes: outputs.reduce((n, o) => n + o.bytes, 0),
    assetTargets: 2, outputs})),
  readImage: async () => {
    reads++; return Buffer.from(bytes);
  }};
  return {input, reads: () => reads};
}
