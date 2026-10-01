/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";

export const CHAT_MEDIA_EXPIRY_JOBS = "chatMediaExpiryJobs";
export const CHAT_MEDIA_EXPIRY_CONTRACT_VERSION = 1;
export const CHAT_MEDIA_RETENTION_MILLIS = 7 * 24 * 60 * 60 * 1000;
export const CHAT_MEDIA_EXPIRY_LEASE_MILLIS = 10 * 60 * 1000;
export const CHAT_MEDIA_EXPIRY_RETRY_ATTEMPTS = 3;
export const CHAT_MEDIA_EXPIRY_RETRY_INTERVAL_MILLIS = 60 * 60 * 1000;
export const CHAT_MEDIA_EXPIRY_QUERY_LIMIT = 50;
export const CHAT_MEDIA_EXPIRY_MAX_JOBS_PER_RUN = 200;
export const CHAT_MEDIA_EXPIRY_MAX_CONCURRENCY = 4;
export const CHAT_MEDIA_EXPIRY_START_BUDGET_MILLIS = 4 * 60 * 1000;
export const CHAT_MEDIA_EXPIRY_FUNCTION_TIMEOUT_SECONDS = 5 * 60;

export type ChatMediaExpiryObject = {
  bucket: string;
  path: string;
  generation: string;
  role: "original" | "thumbnail";
};

export type ChatMediaExpiryJob = {
  schemaVersion: number;
  roomID: string;
  messageID: string;
  sentAt: Timestamp;
  mediaExpiresAt: Timestamp;
  objects: ChatMediaExpiryObject[];
};

export function chatMediaExpiryJobID(
  roomID: string,
  messageID: string,
): string {
  return createHash("sha256").update(`${roomID}\0${messageID}`).digest("hex");
}

export function nextChatMediaExpiryAttemptAt(now: Date): Timestamp {
  const interval = CHAT_MEDIA_EXPIRY_RETRY_INTERVAL_MILLIS;
  const nextHour = Math.floor(now.getTime() / interval) + 1;
  return Timestamp.fromMillis(nextHour * interval);
}

export function chatMediaExpiryNextAttemptAt(
  mediaExpiresAt: Timestamp,
  now: Date,
): Timestamp {
  return mediaExpiresAt.toMillis() > now.getTime() ?
    mediaExpiresAt : Timestamp.fromDate(now);
}
