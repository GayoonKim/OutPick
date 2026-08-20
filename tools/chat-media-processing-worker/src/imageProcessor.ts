import {mkdir, stat} from "node:fs/promises";
import path from "node:path";

import sharp, {type Metadata} from "sharp";

import {MEDIA_PROCESSING_CONTRACT, MediaProcessingError} from "./contracts.js";

const FORMAT_MIME_TYPES: Readonly<Record<string, readonly string[]>> = Object.freeze({
  jpeg: Object.freeze(["image/jpeg"]),
  png: Object.freeze(["image/png"]),
  gif: Object.freeze(["image/gif"]),
  heif: Object.freeze(["image/heic", "image/heif"]),
});

export interface ImageProbe {
  readonly format: "jpeg" | "png" | "gif" | "heif";
  readonly width: number;
  readonly height: number;
  readonly frameCount: number;
  readonly frameHeight: number;
  readonly framePixels: number;
  readonly decodedPixels: number;
  readonly animated: boolean;
  readonly hasAlpha: boolean;
  readonly hasRemovableMetadata: boolean;
}

export interface ImageProcessingResult {
  readonly kind: "image";
  readonly normalizedPath: string;
  readonly thumbnailPath: string;
  readonly normalizedBytes: number;
  readonly thumbnailBytes: number;
  readonly probe: ImageProbe;
  readonly outputFormat: "jpeg" | "png" | "gif";
  readonly metadataRemovalVersion: number;
}

export interface ImageMetadataInput {
  readonly format?: string;
  readonly width?: number;
  readonly height?: number;
  readonly pages?: number;
  readonly pageHeight?: number;
  readonly hasAlpha?: boolean;
  readonly exif?: Buffer;
  readonly icc?: Buffer;
  readonly iptc?: Buffer;
  readonly xmp?: Buffer;
}

function requirePositiveInteger(value: number | undefined, field: string): number {
  if (!Number.isInteger(value) || (value ?? 0) <= 0) {
    throw new MediaProcessingError("invalidMedia", `이미지 ${field} 값이 올바르지 않습니다.`);
  }
  return value as number;
}

export function validateImageMetadata(metadata: ImageMetadataInput, declaredMimeType?: string): ImageProbe {
  const format = metadata.format;
  if (format === undefined || !(format in FORMAT_MIME_TYPES)) {
    throw new MediaProcessingError("unsupportedMedia", "지원하지 않는 이미지 형식입니다.");
  }

  const acceptedMimeTypes = FORMAT_MIME_TYPES[format];
  const normalizedMimeType = declaredMimeType?.trim().toLowerCase();
  if (normalizedMimeType !== undefined && !acceptedMimeTypes.includes(normalizedMimeType)) {
    throw new MediaProcessingError("invalidMedia", "선언한 MIME과 실제 이미지 형식이 다릅니다.");
  }

  const width = requirePositiveInteger(metadata.width, "너비");
  const rawHeight = requirePositiveInteger(metadata.height, "높이");
  const frameCount = metadata.pages ?? 1;
  const frameHeight = metadata.pageHeight ?? rawHeight;
  requirePositiveInteger(frameCount, "프레임 수");
  requirePositiveInteger(frameHeight, "프레임 높이");

  const animated = format === "gif" && frameCount > 1;
  const framePixels = width * frameHeight;
  const decodedPixels = framePixels * frameCount;
  const limits = MEDIA_PROCESSING_CONTRACT.image;

  if (!Number.isSafeInteger(decodedPixels)) {
    throw new MediaProcessingError("resourceLimit", "디코딩 픽셀 수를 안전하게 계산할 수 없습니다.");
  }
  if (!animated && framePixels > limits.maxStaticInputPixels) {
    throw new MediaProcessingError("resourceLimit", "정적 이미지 픽셀 상한을 초과했습니다.", {
      details: {framePixels, limit: limits.maxStaticInputPixels},
    });
  }
  if (animated && frameCount > limits.maxAnimatedFrames) {
    throw new MediaProcessingError("resourceLimit", "GIF 프레임 수 상한을 초과했습니다.", {
      details: {frameCount, limit: limits.maxAnimatedFrames},
    });
  }
  if (animated && framePixels > limits.maxAnimatedFramePixels) {
    throw new MediaProcessingError("resourceLimit", "GIF 프레임당 픽셀 상한을 초과했습니다.", {
      details: {framePixels, limit: limits.maxAnimatedFramePixels},
    });
  }
  if (animated && decodedPixels > limits.maxAnimatedDecodedPixels) {
    throw new MediaProcessingError("resourceLimit", "GIF 총 디코딩 픽셀 상한을 초과했습니다.", {
      details: {decodedPixels, limit: limits.maxAnimatedDecodedPixels},
    });
  }

  return {
    format: format as ImageProbe["format"],
    width,
    height: frameHeight,
    frameCount,
    frameHeight,
    framePixels,
    decodedPixels,
    animated,
    hasAlpha: metadata.hasAlpha ?? false,
    hasRemovableMetadata: Boolean(metadata.exif || metadata.icc || metadata.iptc || metadata.xmp),
  };
}

async function readMetadata(inputPath: string, animated: boolean): Promise<Metadata> {
  try {
    return await sharp(inputPath, {
      animated,
      failOn: "error",
      limitInputPixels: MEDIA_PROCESSING_CONTRACT.image.sharpLimitInputPixels,
    }).metadata();
  } catch (error) {
    throw new MediaProcessingError("invalidMedia", "이미지를 디코딩할 수 없습니다.", {cause: error});
  }
}

export async function probeImage(inputPath: string, declaredMimeType?: string): Promise<ImageProbe> {
  const metadata = await readMetadata(inputPath, true);
  return validateImageMetadata(metadata, declaredMimeType);
}

export async function assertImageMetadataRemoved(outputPath: string): Promise<void> {
  const metadata = await readMetadata(outputPath, true);
  if (metadata.exif || metadata.icc || metadata.iptc || metadata.xmp) {
    throw new MediaProcessingError("processingFailed", "정규화 이미지에 제거 대상 metadata가 남았습니다.");
  }
}

export async function processImage(
  inputPath: string,
  outputDirectory: string,
  declaredMimeType?: string,
): Promise<ImageProcessingResult> {
  const probe = await probeImage(inputPath, declaredMimeType);
  if (probe.format === "heif") {
    throw new MediaProcessingError(
      "unsupportedMedia",
      "HEIC/HEIF 원본은 iOS에서 JPEG로 정규화한 뒤 업로드해야 합니다.",
    );
  }
  await mkdir(outputDirectory, {recursive: true});

  const outputFormat: ImageProcessingResult["outputFormat"] = probe.animated ?
    "gif" : probe.hasAlpha ? "png" : "jpeg";
  const extension = outputFormat === "jpeg" ? "jpg" : outputFormat;
  const normalizedPath = path.join(outputDirectory, `normalized.${extension}`);
  const thumbnailPath = path.join(outputDirectory, "thumbnail.jpg");
  const sourceOptions = {
    animated: probe.animated,
    failOn: "error" as const,
    limitInputPixels: MEDIA_PROCESSING_CONTRACT.image.sharpLimitInputPixels,
  };

  let normalized = sharp(inputPath, sourceOptions)
    .rotate()
    .toColourspace("srgb")
    .resize({
      width: MEDIA_PROCESSING_CONTRACT.image.maxLongEdgePixels,
      height: MEDIA_PROCESSING_CONTRACT.image.maxLongEdgePixels,
      fit: "inside",
      withoutEnlargement: true,
    });

  if (outputFormat === "gif") {
    normalized = normalized.gif({effort: 3, reuse: true, keepDuplicateFrames: true});
  } else if (outputFormat === "png") {
    normalized = normalized.png({compressionLevel: 9});
  } else {
    normalized = normalized.jpeg({quality: 85, mozjpeg: true});
  }
  normalized = normalized.timeout({
    seconds: MEDIA_PROCESSING_CONTRACT.image.maxProcessingMilliseconds / 1000,
  });
  await normalized.toFile(normalizedPath);

  await sharp(inputPath, {
    page: 0,
    failOn: "error",
    limitInputPixels: MEDIA_PROCESSING_CONTRACT.image.sharpLimitInputPixels,
  })
    .rotate()
    .toColourspace("srgb")
    .resize({
      width: MEDIA_PROCESSING_CONTRACT.image.thumbnailLongEdgePixels,
      height: MEDIA_PROCESSING_CONTRACT.image.thumbnailLongEdgePixels,
      fit: "inside",
      withoutEnlargement: true,
    })
    .flatten({background: "#000000"})
    .jpeg({quality: 75, mozjpeg: true})
    .timeout({seconds: MEDIA_PROCESSING_CONTRACT.image.maxProcessingMilliseconds / 1000})
    .toFile(thumbnailPath);

  const [normalizedStat, thumbnailStat] = await Promise.all([
    stat(normalizedPath),
    stat(thumbnailPath),
    assertImageMetadataRemoved(normalizedPath),
    assertImageMetadataRemoved(thumbnailPath),
  ]);
  if (normalizedStat.size > MEDIA_PROCESSING_CONTRACT.image.maxOutputBytes) {
    throw new MediaProcessingError("outputTooLarge", "정규화 이미지가 15 MiB를 초과했습니다.", {
      details: {bytes: normalizedStat.size},
    });
  }

  const normalizedProbe = await probeImage(normalizedPath);
  if (probe.animated && normalizedProbe.frameCount !== probe.frameCount) {
    throw new MediaProcessingError("processingFailed", "GIF 애니메이션 프레임이 보존되지 않았습니다.");
  }

  return {
    kind: "image",
    normalizedPath,
    thumbnailPath,
    normalizedBytes: normalizedStat.size,
    thumbnailBytes: thumbnailStat.size,
    probe,
    outputFormat,
    metadataRemovalVersion: MEDIA_PROCESSING_CONTRACT.metadataRemovalVersion,
  };
}
