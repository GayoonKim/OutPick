import assert from "node:assert/strict";
import {mkdtemp, writeFile} from "node:fs/promises";
import {createRequire} from "node:module";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import sharp from "sharp";

import {runProcess} from "./processRunner.js";
import {probeVideo, processVideo, type VideoRuntime} from "./videoProcessor.js";

const require = createRequire(import.meta.url);
const ffmpegPath = require("ffmpeg-static") as string | null;
const ffprobeStatic = require("ffprobe-static") as {readonly path: string};
const runtime: VideoRuntime = {
  ffmpegPath: process.env.FFMPEG_PATH ?? ffmpegPath ?? "ffmpeg",
  ffprobePath: process.env.FFPROBE_PATH ?? ffprobeStatic.path,
};

test("1시간 H.264/AAC MP4를 재인코딩 없이 remux하고 metadata와 부가 stream을 제거한다", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-video-"));
  const inputPath = path.join(directory, "long-with-metadata.mp4");
  const subtitlePath = path.join(directory, "auxiliary.srt");
  await writeFile(subtitlePath, "1\n00:00:00,000 --> 00:00:01,000\nfixture\n", "utf8");

  await runProcess(runtime.ffmpegPath, [
    "-nostdin", "-v", "error", "-y",
    "-f", "lavfi", "-i", "color=c=black:s=320x180:r=1",
    "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono",
    "-f", "srt", "-i", subtitlePath,
    "-t", "3600",
    "-map", "0:v:0", "-map", "1:a:0", "-map", "2:s:0",
    "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "16k",
    "-c:s", "mov_text",
    "-metadata", "title=OutPick private fixture",
    "-metadata", "location=+37.0+127.0/",
    inputPath,
  ], 10 * 60_000);

  const result = await processVideo(inputPath, path.join(directory, "output"), runtime);
  const output = await probeVideo(result.normalizedPath, runtime);
  const thumbnail = await sharp(result.thumbnailPath).metadata();

  assert.equal(result.processingMode, "streamCopyRemux");
  assert.equal(result.probe.videoCodec, "h264");
  assert.equal(result.probe.audioCodec, "aac");
  assert.equal(result.probe.sourceStreamCount, 3);
  assert.equal(output.probe.sourceStreamCount, 2);
  assert.deepEqual(output.probe.removableMetadataKeys, []);
  assert.ok(result.probe.durationSeconds >= 3599);
  assert.ok(result.probe.removableMetadataKeys.includes("title"));
  assert.ok(result.probe.removableMetadataKeys.some((key) => key.includes("location")));
  assert.equal(result.thumbnailAtSeconds, 1);
  assert.ok(result.thumbnailBytes > 0);
  assert.ok((thumbnail.width ?? 0) <= 512);
  assert.ok((thumbnail.height ?? 0) <= 512);
  assert.equal(thumbnail.format, "jpeg");
});
