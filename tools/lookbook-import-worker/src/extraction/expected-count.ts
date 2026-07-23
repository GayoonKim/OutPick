import {extractionSourceEvidence} from "./evidence.js";

export type ExpectedCountEvidence = {
  kind:
    | "declared_script_total"
    | "rendered_gallery_count"
    | "counter_text"
    | "structured_data_count"
    | "admin_confirmed";
  value: number;
  confidence: number;
  sourceFingerprint: string;
};

const SCRIPT_TOTAL_PATTERNS = [
  /\btotal\s*[:=]\s*["']?(\d{1,4})["']?/gi,
  /\b(?:imageCount|galleryCount|slideCount)\s*[:=]\s*["']?(\d{1,4})["']?/gi,
];

export function collectExpectedCountEvidence(
  html: string,
  sourceURL: string,
): ExpectedCountEvidence[] {
  const sourceFingerprint = extractionSourceEvidence(sourceURL).fingerprint;
  return declaredScriptTotals(html).map((value) => ({
    kind: "declared_script_total",
    value,
    confidence: 0.82,
    sourceFingerprint,
  }));
}

export function declaredScriptTotals(html: string): number[] {
  const values = new Set<number>();
  for (const pattern of SCRIPT_TOTAL_PATTERNS) {
    for (const match of html.matchAll(pattern)) {
      const value = Number(match[1]);
      if (Number.isSafeInteger(value) && value > 0) {
        values.add(value);
      }
    }
  }
  return Array.from(values);
}
