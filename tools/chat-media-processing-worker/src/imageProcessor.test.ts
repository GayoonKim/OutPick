import assert from "node:assert/strict";
import {mkdtemp} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import sharp from "sharp";

import {MEDIA_PROCESSING_CONTRACT, MediaProcessingError} from "./contracts.js";
import {createFixtureCorpus} from "./fixtures.js";
import {processImage, probeImage, validateImageMetadata} from "./imageProcessor.js";

async function temporaryDirectory(): Promise<string> {
  return await mkdtemp(path.join(os.tmpdir(), "outpick-chat-media-image-"));
}

test("JPEG metadata를 제거하고 JPEG와 thumbnail을 생성한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));
  const before = await sharp(fixtures.jpegWithMetadata).metadata();
  assert.ok(before.exif);

  const result = await processImage(fixtures.jpegWithMetadata, path.join(directory, "output"), "image/jpeg");

  assert.equal(result.outputFormat, "jpeg");
  assert.equal(result.probe.hasRemovableMetadata, true);
  const normalizedMetadata = await sharp(result.normalizedPath).metadata();
  assert.equal(normalizedMetadata.exif, undefined);
  assert.equal(normalizedMetadata.width, 32);
  assert.equal(normalizedMetadata.height, 64);
  assert.equal(normalizedMetadata.space, "srgb");
  assert.equal((await sharp(result.thumbnailPath).metadata()).exif, undefined);
});

test("alpha PNG는 투명도를 보존하는 PNG로 정규화한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));

  const result = await processImage(fixtures.pngWithAlpha, path.join(directory, "output"), "image/png");

  assert.equal(result.outputFormat, "png");
  assert.equal((await sharp(result.normalizedPath).metadata()).hasAlpha, true);
});

test("animated GIF는 모든 frame을 보존한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));

  const result = await processImage(fixtures.animatedGif, path.join(directory, "output"), "image/gif");
  const output = await probeImage(result.normalizedPath);

  assert.equal(result.outputFormat, "gif");
  assert.equal(result.probe.frameCount, 2);
  assert.equal(output.frameCount, 2);
});

test("raw HEIC는 실제 형식 판별 후 unsupportedMedia로 거부한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));

  const probe = await probeImage(fixtures.heic, "image/heic");
  assert.equal(probe.format, "heif");

  await assert.rejects(
    processImage(fixtures.heic, path.join(directory, "output"), "image/heic"),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "unsupportedMedia",
  );
});

test("선언 MIME과 실제 형식이 다르면 invalidMedia로 거부한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));

  await assert.rejects(
    processImage(fixtures.jpegWithMetadata, path.join(directory, "output"), "image/png"),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "invalidMedia",
  );
});

test("손상 이미지는 invalidMedia로 거부한다", async () => {
  const directory = await temporaryDirectory();
  const fixtures = await createFixtureCorpus(path.join(directory, "fixtures"));

  await assert.rejects(
    processImage(fixtures.corruptImage, path.join(directory, "output"), "image/jpeg"),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "invalidMedia",
  );
});

test("GIF frame과 decoded pixel 상한을 deterministic하게 거부한다", () => {
  assert.throws(
    () => validateImageMetadata({
      format: "gif",
      width: 100,
      height: 100 * (MEDIA_PROCESSING_CONTRACT.image.maxAnimatedFrames + 1),
      pages: MEDIA_PROCESSING_CONTRACT.image.maxAnimatedFrames + 1,
      pageHeight: 100,
    }),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "resourceLimit",
  );

  assert.throws(
    () => validateImageMetadata({
      format: "gif",
      width: 1000,
      height: 100 * 101,
      pages: 101,
      pageHeight: 1000,
    }),
    (error: unknown) => error instanceof MediaProcessingError && error.code === "resourceLimit",
  );
});
