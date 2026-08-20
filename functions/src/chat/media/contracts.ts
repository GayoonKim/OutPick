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
  const production = projectID === "outpick-664ae";
  const count = kind === "images" ? (production ? 4 : 1) : 1;
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
