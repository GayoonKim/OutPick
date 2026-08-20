export const MEBIBYTE = 1024 * 1024;

export const MEDIA_PROCESSING_CONTRACT = Object.freeze({
  schemaVersion: 1,
  metadataRemovalVersion: 1,
  runtime: Object.freeze({
    cpu: 2,
    memoryMiB: 1024,
    attachmentConcurrency: 1,
  }),
  image: Object.freeze({
    maxLongEdgePixels: 4096,
    maxOutputBytes: 15 * MEBIBYTE,
    sharpLimitInputPixels: 100_000_000,
    maxStaticInputPixels: 64_000_000,
    maxAnimatedFrames: 200,
    maxAnimatedFramePixels: 16_777_216,
    maxAnimatedDecodedPixels: 100_000_000,
    thumbnailLongEdgePixels: 512,
    maxProcessingMilliseconds: 60_000,
  }),
  video: Object.freeze({
    maxOutputBytes: 350 * MEBIBYTE,
    allowedVideoCodecs: Object.freeze(["h264"]),
    allowedAudioCodecs: Object.freeze(["aac"]),
    thumbnailLongEdgePixels: 512,
    maxRemuxMilliseconds: 10 * 60_000,
  }),
});

export type MediaProcessingFailureCode =
  | "invalidInput"
  | "invalidMedia"
  | "unsupportedMedia"
  | "resourceLimit"
  | "outputTooLarge"
  | "processingFailed"
  | "runtimeUnavailable";

export class MediaProcessingError extends Error {
  readonly code: MediaProcessingFailureCode;
  readonly retryable: boolean;
  readonly details?: Readonly<Record<string, string | number | boolean>>;

  constructor(
    code: MediaProcessingFailureCode,
    message: string,
    options: {
      retryable?: boolean;
      cause?: unknown;
      details?: Readonly<Record<string, string | number | boolean>>;
    } = {},
  ) {
    super(message, {cause: options.cause});
    this.name = "MediaProcessingError";
    this.code = code;
    this.retryable = options.retryable ?? false;
    this.details = options.details;
  }
}

export function classifyUnexpectedProcessingError(error: unknown): MediaProcessingError {
  if (error instanceof MediaProcessingError) {
    return error;
  }

  return new MediaProcessingError(
    "processingFailed",
    "미디어 처리 중 예상하지 못한 오류가 발생했습니다.",
    {retryable: true, cause: error},
  );
}
