/* eslint-disable require-jsdoc */

export const MODERATION_SCHEMA_VERSION = 1;
export const MODERATION_HMAC_KEY_VERSION = 1;

export type ModerationProvider = "google" | "apple" | "kakao";
export type ModerationStatus = "active" | "restricted" | "suspended";

export const moderationCapabilities = {
  active: [
    "readAppContent",
    "createUGC",
    "updateUGC",
    "deleteOwnUGC",
    "createRoom",
    "joinRoom",
    "moderateOwnedRoom",
    "report",
    "block",
    "unblock",
    "support",
    "deleteAccount",
  ],
  restricted: [
    "readAppContent",
    "deleteOwnUGC",
    "report",
    "block",
    "unblock",
    "support",
    "deleteAccount",
  ],
  suspended: [
    "support",
    "deleteAccount",
  ],
} as const satisfies Record<ModerationStatus, readonly string[]>;

export interface ProviderIdentity {
  provider: ModerationProvider;
  subject: string;
}

export interface ModerationHmacKey {
  version: number;
  secret: string;
}

export interface ModerationState {
  moderationStatus: ModerationStatus;
  restrictedUntil: Date | null;
  stateVersion: number;
  noticeReasonCode: string | null;
}

export interface ModerationStateResponse {
  moderationStatus: ModerationStatus;
  restrictedUntil: string | null;
  allowedCapabilities: readonly string[];
  noticeReasonCode: string | null;
  supportURL: string | null;
}
