import {mkdtemp} from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import sharp from "sharp";

import {MediaProcessingError} from "./contracts.js";
import {createFixtureCorpus} from "./fixtures.js";
import {processImage} from "./imageProcessor.js";
import {runProcess} from "./processRunner.js";
import {DEFAULT_VIDEO_RUNTIME, processVideo} from "./videoProcessor.js";

async function main(): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-runtime-"));
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));
  const ffmpegVersion = await runProcess(DEFAULT_VIDEO_RUNTIME.ffmpegPath, ["-version"]);
  const ffprobeVersion = await runProcess(DEFAULT_VIDEO_RUNTIME.ffprobePath, ["-version"]);
  const heifProbe = await processImage(fixtures.heic, path.join(directory, "heic"), "image/heic")
    .then(() => "unexpectedAccepted" as const)
    .catch((error: unknown) => {
      if (error instanceof MediaProcessingError && error.code === "unsupportedMedia") {
        return "rejectedByTransportContract" as const;
      }
      throw error;
    });

  const imageResults = await Promise.all([
    processImage(fixtures.jpegWithMetadata, path.join(directory, "jpeg"), "image/jpeg"),
    processImage(fixtures.pngWithAlpha, path.join(directory, "png"), "image/png"),
    processImage(fixtures.animatedGif, path.join(directory, "gif"), "image/gif"),
  ]);

  const longVideoPath = path.join(directory, "long-with-metadata.mp4");
  await runProcess(DEFAULT_VIDEO_RUNTIME.ffmpegPath, [
    "-nostdin", "-v", "error", "-y",
    "-f", "lavfi", "-i", "color=c=black:s=320x180:r=1",
    "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono",
    "-t", "3600",
    "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "16k",
    "-metadata", "title=OutPick private fixture",
    "-metadata", "location=+37.0+127.0/",
    longVideoPath,
  ], 10 * 60_000);
  const videoResult = await processVideo(longVideoPath, path.join(directory, "video"), DEFAULT_VIDEO_RUNTIME);

  process.stdout.write(`${JSON.stringify({
    node: process.version,
    sharp: sharp.versions.sharp,
    libvips: sharp.versions.vips,
    ffmpeg: ffmpegVersion.stdout.split("\n")[0],
    ffprobe: ffprobeVersion.stdout.split("\n")[0],
    heifContainerProbeCapability: sharp.format.heif.input.file,
    rawHeicTransport: heifProbe,
    images: imageResults.map((result) => ({
      inputFormat: result.probe.format,
      outputFormat: result.outputFormat,
      frameCount: result.probe.frameCount,
      outputBytes: result.normalizedBytes,
    })),
    video: {
      durationSeconds: videoResult.probe.durationSeconds,
      processingMode: videoResult.processingMode,
      inputMetadataKeys: videoResult.probe.removableMetadataKeys,
      outputBytes: videoResult.normalizedBytes,
    },
  }, null, 2)}\n`);
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
