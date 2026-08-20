import {mkdir, mkdtemp} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {performance} from "node:perf_hooks";

import sharp from "sharp";

import {MEDIA_PROCESSING_CONTRACT} from "./contracts.js";
import {processImage} from "./imageProcessor.js";
import {runProcess} from "./processRunner.js";

async function main(): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-benchmark-"));
  const inputDirectory = path.join(directory, "inputs");
  await mkdir(inputDirectory, {recursive: true});
  const imagePaths: string[] = [];
  const setupStartedAt = performance.now();

  for (let index = 0; index < 30; index += 1) {
    const inputPath = path.join(inputDirectory, `${index}.jpg`);
    await sharp({
      create: {
        width: 4096,
        height: 4096,
        channels: 3,
        background: {r: index * 7 % 255, g: index * 13 % 255, b: index * 19 % 255},
      },
    }).jpeg({quality: 95}).toFile(inputPath);
    imagePaths.push(inputPath);
  }

  const processStartedAt = performance.now();
  for (const [index, inputPath] of imagePaths.entries()) {
    await processImage(inputPath, path.join(directory, "outputs", `${index}`), "image/jpeg");
  }
  const completedAt = performance.now();

  const gifPath = path.join(directory, "candidate.gif");
  await runProcess(process.env.FFMPEG_PATH ?? "ffmpeg", [
    "-nostdin", "-v", "error", "-y",
    "-f", "lavfi", "-i", "testsrc=size=1024x512:rate=10",
    "-t", "19",
    gifPath,
  ], 10 * 60_000);
  const gifStartedAt = performance.now();
  const gifResult = await processImage(gifPath, path.join(directory, "gif-output"), "image/gif");
  const gifCompletedAt = performance.now();

  process.stdout.write(`${JSON.stringify({
    runtime: {
      node: process.version,
      sharp: sharp.versions.sharp,
      libvips: sharp.versions.vips,
    },
    limits: MEDIA_PROCESSING_CONTRACT.image,
    staticImages: {
      count: imagePaths.length,
      dimensions: "4096x4096",
      fixtureSetupMilliseconds: Math.round(setupStartedAt <= processStartedAt ? processStartedAt - setupStartedAt : 0),
      processingMilliseconds: Math.round(completedAt - processStartedAt),
    },
    animatedGif: {
      dimensions: `${gifResult.probe.width}x${gifResult.probe.height}`,
      frameCount: gifResult.probe.frameCount,
      decodedPixels: gifResult.probe.decodedPixels,
      processingMilliseconds: Math.round(gifCompletedAt - gifStartedAt),
    },
    processResourceUsage: process.resourceUsage(),
    memoryUsage: process.memoryUsage(),
  }, null, 2)}\n`);
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
