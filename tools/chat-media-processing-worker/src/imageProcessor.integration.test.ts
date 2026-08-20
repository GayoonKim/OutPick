import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {mkdtemp} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import sharp from "sharp";

import {MediaProcessingError} from "./contracts.js";
import {processImage} from "./imageProcessor.js";
import {runProcess} from "./processRunner.js";

const require = createRequire(import.meta.url);
const ffmpegPath = process.env.FFMPEG_PATH ??
  (require("ffmpeg-static") as string | null) ??
  "ffmpeg";

test("실제 201-frame GIF는 decode 전에 resourceLimit으로 거부한다", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-gif-"));
  const inputPath = path.join(directory, "too-many-frames.gif");
  await runProcess(ffmpegPath, [
    "-nostdin", "-v", "error", "-y",
    "-f", "lavfi", "-i", "testsrc=size=64x64:rate=10",
    "-frames:v", "201",
    inputPath,
  ], 60_000);

  await assert.rejects(
    processImage(inputPath, path.join(directory, "output"), "image/gif"),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "resourceLimit",
  );
});

test("연속 중복 GIF frame의 수와 delay, loop를 보존한다", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-gif-duplicate-"));
  const inputPath = path.join(directory, "duplicate-frames.gif");
  await runProcess(ffmpegPath, [
    "-nostdin", "-v", "error", "-y",
    "-f", "lavfi", "-i", "color=c=red:s=64x64:r=25:d=1",
    "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=25:d=1",
    "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0",
    "-loop", "0",
    inputPath,
  ], 60_000);

  const inputMetadata = await sharp(inputPath, {animated: true}).metadata();
  const result = await processImage(inputPath, path.join(directory, "output"), "image/gif");
  const outputMetadata = await sharp(result.normalizedPath, {animated: true}).metadata();

  assert.equal(inputMetadata.pages, 50);
  assert.equal(outputMetadata.pages, inputMetadata.pages);
  assert.deepEqual(outputMetadata.delay, inputMetadata.delay);
  assert.equal(outputMetadata.loop, inputMetadata.loop);
});
