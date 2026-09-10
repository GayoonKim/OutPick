/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";

export const CHAT_MEDIA_CONTRACT_VERSION = 2;
export const CHAT_MEDIA_AUTOMATIC_ATTEMPTS = 3;
export const CHAT_MEDIA_EXECUTION_LEASE_MILLIS = 45 * 60 * 1000;
export const CHAT_MEDIA_TERMINAL_RETENTION_MILLIS = 7 * 24 * 60 * 60 * 1000;
export const CHAT_MEDIA_DELIVERY_RETENTION_MILLIS = 7 * 24 * 60 * 60 * 1000;

export type ChatMediaKind = "images" | "video";
export type ChatMediaProcessingStatus =
  "uploading" | "queued" | "processing" |
  "ready" | "canceled" | "failed" | "expired";

export const CHAT_MEDIA_TERMINAL_STATUSES = new Set<ChatMediaProcessingStatus>([
  "ready", "canceled", "failed", "expired",
]);

export function processingSlotIDs(
  projectID: string,
  kind: ChatMediaKind
): string[] {
  // 프로젝트별 자원 확대는 배포 환경 설정으로 조절하며 초기 전체 실행량은 1이다.
  const key = kind === "images" ?
    "CHAT_MEDIA_IMAGE_EXECUTION_LIMIT" : "CHAT_MEDIA_VIDEO_EXECUTION_LIMIT";
  const configured = Number(process.env[key] ?? "1");
  if (!Number.isInteger(configured) || configured < 1 || configured > 100) {
    throw new Error(`Invalid ${key} for ${projectID}`);
  }
  const count = configured;
  const prefix = kind === "images" ? "image" : "video";
  return Array.from({length: count}, (_, index) => `${prefix}-${index}`);
}

export function deterministicMediaTaskID(
  uploadPath: string,
  dispatchGeneration: number
): string {
  const digest = createHash("sha256")
    .update(`${uploadPath}:${dispatchGeneration}`)
    .digest("hex")
    .slice(0, 40);
  return `chat-media-${digest}`;
}

export function isChatMediaKind(value: unknown): value is ChatMediaKind {
  return value === "images" || value === "video";
}

export function isActiveProcessingStatus(
  value: unknown
): value is "uploading" | "queued" | "processing" {
  return value === "uploading" || value === "queued" || value === "processing";
}
