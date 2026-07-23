import {createHash} from "node:crypto";

export type ExtractionSourceEvidence = {
  origin: string;
  path: string;
  queryKeys: string[];
  fingerprint: string;
};

export function extractionSourceEvidence(
  sourceURL: string,
): ExtractionSourceEvidence {
  const url = new URL(sourceURL);
  const queryKeys = Array.from(
    new Set(url.searchParams.keys()),
  ).sort();
  const maskedQuery = queryKeys.map((key) => `${key}=*`).join("&");
  const redacted = `${url.origin}${url.pathname}` +
    (maskedQuery.length > 0 ? `?${maskedQuery}` : "");
  return {
    origin: url.origin,
    path: url.pathname,
    queryKeys,
    fingerprint: createHash("sha256")
      .update(redacted)
      .digest("hex")
      .slice(0, 24),
  };
}

export function extractionCandidateKey(candidateURL: string): string {
  return extractionSourceEvidence(candidateURL).fingerprint;
}
