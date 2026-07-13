/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";

export function canonicalBrandName(rawName: string): string {
  return rawName.normalize("NFKC").trim().replace(/\s+/g, " ");
}

export function normalizedBrandName(rawName: string): string {
  const normalized = canonicalBrandName(rawName).toLocaleLowerCase();
  if (normalized.length === 0) {
    throw new HttpsError("invalid-argument", "name 값이 올바르지 않습니다.");
  }
  return normalized;
}

export function normalizedHTTPURL(
  rawValue: string,
  fieldName: string
): string {
  const candidate = rawValue.includes("://") ? rawValue : `https://${rawValue}`;
  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    throw new HttpsError("invalid-argument", `${fieldName} 값이 올바르지 않습니다.`);
  }
  const protocol = parsed.protocol.toLowerCase();
  if (protocol !== "http:" && protocol !== "https:") {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} 값은 http 또는 https만 지원합니다.`
    );
  }
  if (!parsed.hostname) {
    throw new HttpsError("invalid-argument", `${fieldName} 값에 도메인이 필요합니다.`);
  }
  parsed.protocol = protocol;
  parsed.hostname = parsed.hostname.toLowerCase();
  return parsed.toString();
}
