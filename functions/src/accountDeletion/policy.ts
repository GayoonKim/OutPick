/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  AccountDeletionAuthContext,
  AccountDeletionIntentInput,
  AccountDeletionReceiptInput,
} from "./contracts.js";

export const DELETION_INTENT_TTL_MS = 5 * 60 * 1000;
export const RECENT_AUTH_MAX_AGE_SECONDS = 10 * 60;
export const DELETION_PROCESSING_MS = 7 * 24 * 60 * 60 * 1000;

function requiredShortString(
  data: Record<string, unknown>,
  key: string,
): string {
  const value = data[key];
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 필요합니다.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 256 || trimmed.includes("/")) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return trimmed;
}

export function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function deletionRequestID(
  uid: string,
  accountGenerationID: string,
): string {
  return sha256(`outpick-account-deletion-v1|${uid}|${accountGenerationID}`);
}

export function parseIntentInput(data: unknown): AccountDeletionIntentInput {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "삭제 intent가 필요합니다.");
  }
  const record = data as Record<string, unknown>;
  return {
    intentID: requiredShortString(record, "intentID"),
    nonce: requiredShortString(record, "nonce"),
  };
}

export function parseReceiptInput(data: unknown): AccountDeletionReceiptInput {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "삭제 영수증이 필요합니다.");
  }
  const record = data as Record<string, unknown>;
  return {
    requestID: requiredShortString(record, "requestID"),
    receiptToken: requiredShortString(record, "receiptToken"),
  };
}

export function requireRecentAuth(
  context: AccountDeletionAuthContext,
  nowMillis: number,
): void {
  const nowSeconds = Math.floor(nowMillis / 1000);
  const age = nowSeconds - context.authTimeSeconds;
  if (
    !Number.isFinite(context.authTimeSeconds) ||
    age < 0 ||
    age > RECENT_AUTH_MAX_AGE_SECONDS
  ) {
    throw new HttpsError(
      "unauthenticated",
      "계정 삭제를 위해 다시 로그인해 주세요.",
    );
  }
}

export function canCancelDeletion(
  nowMillis: number,
  cancelableUntilMillis: number,
): boolean {
  return nowMillis < cancelableUntilMillis;
}

export function retryDelayMillis(attemptCount: number): number {
  const exponent = Math.max(0, Math.min(7, attemptCount - 1));
  return Math.min(6 * 60 * 60 * 1000, 5 * 60 * 1000 * (2 ** exponent));
}
