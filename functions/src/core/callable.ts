/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";

export function recordData(data: unknown): Record<string, unknown> {
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "요청 데이터가 올바르지 않습니다.");
  }
  return data as Record<string, unknown>;
}

export function requiredString(
  data: Record<string, unknown>,
  key: string,
  maxLength: number
): string {
  const value = data[key];
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 필요합니다.`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return trimmed;
}

export function optionalString(
  data: Record<string, unknown>,
  key: string,
  maxLength: number
): string | null {
  const value = data[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} 값이 너무 깁니다.`);
  }
  return trimmed;
}

export function requiredBoolean(
  data: Record<string, unknown>,
  key: string
): boolean {
  const value = data[key];
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${key} 값이 필요합니다.`);
  }
  return value;
}

export function requiredAuthUID(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }
  return uid;
}

export function requiredDocumentID(
  rawValue: string,
  fieldName: string
): string {
  const value = rawValue.trim();
  if (value.length === 0 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  return value;
}

export function optionalDocumentID(
  rawValue: string | null,
  fieldName: string
): string | null {
  return rawValue === null ? null : requiredDocumentID(rawValue, fieldName);
}
