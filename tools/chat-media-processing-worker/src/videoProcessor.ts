import {mkdir, stat} from "node:fs/promises";
import path from "node:path";

import {MEDIA_PROCESSING_CONTRACT, MediaProcessingError} from "./contracts.js";
import {runProcess} from "./processRunner.js";

interface FFprobeStream {
  readonly index?: number;
  readonly codec_type?: string;
  readonly codec_name?: string;
  readonly width?: number;
  readonly height?: number;
  readonly duration?: string;
  readonly tags?: Readonly<Record<string, string>>;
  readonly side_data_list?: readonly Readonly<Record<string, unknown>>[];
}

interface FFprobeFormat {
  readonly format_name?: string;
  readonly duration?: string;
  readonly size?: string;
  readonly tags?: Readonly<Record<string, string>>;
}

interface FFprobePayload {
  readonly streams?: readonly FFprobeStream[];
  readonly format?: FFprobeFormat;
}

export interface VideoProbe {
  readonly container: string;
  readonly videoCodec: string;
  readonly audioCodec: string | null;
  readonly width: number;
  readonly height: number;
  readonly durationSeconds: number;
  readonly inputBytes: number;
  readonly sourceStreamCount: number;
  readonly removableMetadataKeys: readonly string[];
}

export interface VideoProcessingResult {
  readonly kind: "video";
  readonly normalizedPath: string;
  readonly normalizedBytes: number;
  readonly thumbnailPath: string;
  readonly thumbnailBytes: number;
  readonly thumbnailAtSeconds: number;
  readonly processingMode: "streamCopyRemux";
  readonly probe: VideoProbe;
  readonly metadataRemovalVersion: number;
}

export interface VideoRuntime {
  readonly ffmpegPath: string;
  readonly ffprobePath: string;
}

export const DEFAULT_VIDEO_RUNTIME: VideoRuntime = Object.freeze({
  ffmpegPath: process.env.FFMPEG_PATH ?? "ffmpeg",
  ffprobePath: process.env.FFPROBE_PATH ?? "ffprobe",
});

const SENSITIVE_METADATA_KEY = /(location|title|artist|comment|description|creation_time|date|make|model|software|copyright)/i;

function parseFiniteNumber(value: string | number | undefined, field: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new MediaProcessingError("invalidMedia", `영상 ${field} 값이 올바르지 않습니다.`);
  }
  return parsed;
}

function metadataKeys(payload: FFprobePayload): string[] {
  const keys = new Set<string>();
  for (const key of Object.keys(payload.format?.tags ?? {})) {
    if (SENSITIVE_METADATA_KEY.test(key)) keys.add(key);
  }
  for (const stream of payload.streams ?? []) {
    for (const key of Object.keys(stream.tags ?? {})) {
      if (SENSITIVE_METADATA_KEY.test(key)) keys.add(key);
    }
  }
  return [...keys].sort();
}

export function parseVideoProbe(payload: FFprobePayload): VideoProbe {
  const streams = payload.streams ?? [];
  const video = streams.find((stream) => stream.codec_type === "video");
  const audio = streams.find((stream) => stream.codec_type === "audio");
  if (video === undefined || video.codec_name === undefined) {
    throw new MediaProcessingError("invalidMedia", "재생 가능한 video stream이 없습니다.");
  }

  const container = payload.format?.format_name ?? "";
  if (!container.split(",").some((name) => ["mov", "mp4"].includes(name))) {
    throw new MediaProcessingError("unsupportedMedia", "MP4/MOV 컨테이너만 지원합니다.");
  }
  if (!MEDIA_PROCESSING_CONTRACT.video.allowedVideoCodecs.some((codec) => codec === video.codec_name)) {
    throw new MediaProcessingError("unsupportedMedia", "지원하지 않는 video codec입니다.", {
      details: {codec: video.codec_name},
    });
  }
  if (audio?.codec_name !== undefined &&
      !MEDIA_PROCESSING_CONTRACT.video.allowedAudioCodecs.some((codec) => codec === audio.codec_name)) {
    throw new MediaProcessingError("unsupportedMedia", "지원하지 않는 audio codec입니다.", {
      details: {codec: audio.codec_name},
    });
  }

  const width = parseFiniteNumber(video.width, "너비");
  const height = parseFiniteNumber(video.height, "높이");
  if (!Number.isInteger(width) || width <= 0 || !Number.isInteger(height) || height <= 0) {
    throw new MediaProcessingError("invalidMedia", "영상 크기가 올바르지 않습니다.");
  }

  return {
    container,
    videoCodec: video.codec_name,
    audioCodec: audio?.codec_name ?? null,
    width,
    height,
    durationSeconds: parseFiniteNumber(payload.format?.duration ?? video.duration, "길이"),
    inputBytes: parseFiniteNumber(payload.format?.size, "파일 크기"),
    sourceStreamCount: streams.length,
    removableMetadataKeys: metadataKeys(payload),
  };
}

export async function probeVideo(
  inputPath: string,
  runtime: VideoRuntime = DEFAULT_VIDEO_RUNTIME,
): Promise<{probe: VideoProbe; raw: FFprobePayload}> {
  const result = await runProcess(runtime.ffprobePath, [
    "-v", "error",
    "-print_format", "json",
    "-show_format",
    "-show_streams",
    inputPath,
  ]);

  try {
    const raw = JSON.parse(result.stdout) as FFprobePayload;
    return {probe: parseVideoProbe(raw), raw};
  } catch (error) {
    if (error instanceof MediaProcessingError) throw error;
    throw new MediaProcessingError("invalidMedia", "ffprobe 결과를 해석할 수 없습니다.", {cause: error});
  }
}

export async function processVideo(
  inputPath: string,
  outputDirectory: string,
  runtime: VideoRuntime = DEFAULT_VIDEO_RUNTIME,
): Promise<VideoProcessingResult> {
  const inputStat = await stat(inputPath);
  if (inputStat.size > MEDIA_PROCESSING_CONTRACT.video.maxOutputBytes) {
    throw new MediaProcessingError("outputTooLarge", "입력 영상이 350 MiB를 초과했습니다.", {
      details: {bytes: inputStat.size},
    });
  }

  const {probe} = await probeVideo(inputPath, runtime);
  await mkdir(outputDirectory, {recursive: true});
  const normalizedPath = path.join(outputDirectory, "normalized.mp4");
  await runProcess(runtime.ffmpegPath, [
    "-nostdin",
    "-v", "error",
    "-y",
    "-i", inputPath,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c", "copy",
    "-map_metadata", "-1",
    "-map_chapters", "-1",
    "-movflags", "+faststart",
    "-f", "mp4",
    normalizedPath,
  ], MEDIA_PROCESSING_CONTRACT.video.maxRemuxMilliseconds);

  const outputStat = await stat(normalizedPath);
  if (outputStat.size > MEDIA_PROCESSING_CONTRACT.video.maxOutputBytes) {
    throw new MediaProcessingError("outputTooLarge", "정규화 영상이 350 MiB를 초과했습니다.", {
      details: {bytes: outputStat.size},
    });
  }

  const normalized = await probeVideo(normalizedPath, runtime);
  if (normalized.probe.videoCodec !== probe.videoCodec || normalized.probe.audioCodec !== probe.audioCodec) {
    throw new MediaProcessingError("processingFailed", "stream-copy 과정에서 codec이 변경되었습니다.");
  }
  if (normalized.probe.removableMetadataKeys.length > 0) {
    throw new MediaProcessingError("processingFailed", "정규화 영상에 제거 대상 metadata가 남았습니다.", {
      details: {metadataKeyCount: normalized.probe.removableMetadataKeys.length},
    });
  }

  const thumbnailAtSeconds = Math.min(1, probe.durationSeconds / 2);
  const thumbnailPath = path.join(outputDirectory, "thumbnail.jpg");
  try {
    await runProcess(runtime.ffmpegPath, [
      "-nostdin",
      "-v", "error",
      "-y",
      "-ss", thumbnailAtSeconds.toFixed(3),
      "-i", normalizedPath,
      "-map", "0:v:0",
      "-frames:v", "1",
      "-vf", `scale=${MEDIA_PROCESSING_CONTRACT.video.thumbnailLongEdgePixels}:` +
        `${MEDIA_PROCESSING_CONTRACT.video.thumbnailLongEdgePixels}:` +
        "force_original_aspect_ratio=decrease:force_divisible_by=2",
      "-q:v", "3",
      "-map_metadata", "-1",
      thumbnailPath,
    ], MEDIA_PROCESSING_CONTRACT.video.maxRemuxMilliseconds);
  } catch (error) {
    throw new MediaProcessingError("invalidMedia", "영상 thumbnail을 생성할 수 없습니다.", {
      cause: error,
    });
  }
  let thumbnailStat;
  try {
    thumbnailStat = await stat(thumbnailPath);
  } catch (error) {
    throw new MediaProcessingError("invalidMedia", "영상 thumbnail을 생성할 수 없습니다.", {
      cause: error,
    });
  }
  if (thumbnailStat.size <= 0) {
    throw new MediaProcessingError("invalidMedia", "영상 thumbnail이 비어 있습니다.");
  }

  return {
    kind: "video",
    normalizedPath,
    normalizedBytes: outputStat.size,
    thumbnailPath,
    thumbnailBytes: thumbnailStat.size,
    thumbnailAtSeconds,
    processingMode: "streamCopyRemux",
    probe,
    metadataRemovalVersion: MEDIA_PROCESSING_CONTRACT.metadataRemovalVersion,
  };
}
