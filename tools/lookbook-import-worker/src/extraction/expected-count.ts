import {extractionSourceEvidence} from "./evidence.js";

export type ExpectedCountEvidence = {
  kind:
    | "declared_script_total"
    | "scoped_gallery_candidate_total"
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
  staticCandidateCount = 0,
): ExpectedCountEvidence[] {
  const sourceFingerprint = extractionSourceEvidence(sourceURL).fingerprint;
  const declared = declaredScriptTotalResult(html);
  const evidence: ExpectedCountEvidence[] = declared.values.map((value) => ({
    kind: "declared_script_total",
    value,
    confidence: 0.82,
    sourceFingerprint,
  }));

  if (declared.addExternalStaticCandidates && staticCandidateCount > 0) {
    for (const value of declared.values) {
      const candidateTotal = value + staticCandidateCount;
      if (evidence.some((item) => item.value === candidateTotal)) {
        continue;
      }
      evidence.push({
        kind: "scoped_gallery_candidate_total",
        value: candidateTotal,
        confidence: 0.8,
        sourceFingerprint,
      });
    }
  }

  return evidence;
}

export function declaredScriptTotals(html: string): number[] {
  return declaredScriptTotalResult(html).values;
}

function declaredScriptTotalResult(html: string): {
  values: number[];
  scoped: boolean;
  addExternalStaticCandidates: boolean;
} {
  const scoped = scopedScriptTotals(html);
  if (scoped.values.length > 0) {
    return {
      values: scoped.values,
      scoped: true,
      addExternalStaticCandidates: scoped.activeContainersAreEmpty,
    };
  }
  return {
    values: globalScriptTotals(html),
    scoped: false,
    addExternalStaticCandidates: false,
  };
}

function scopedScriptTotals(html: string): {
  values: number[];
  activeContainersAreEmpty: boolean;
} {
  const elementIDs = new Set<string>();
  for (const match of html.matchAll(/\bid\s*=\s*["']([^"']+)["']/gi)) {
    const id = match[1]?.trim();
    if (id) {
      elementIDs.add(id);
    }
  }

  const values = new Set<number>();
  const matchedIDs = new Set<string>();
  for (const id of elementIDs) {
    const escapedID = escapeRegExp(id);
    const propertyPattern = new RegExp(
      `(?:^|[,{])\\s*(?:["']${escapedID}["']|${escapedID})` +
        "\\s*:\\s*\\{([\\s\\S]{0,4000}?)\\}",
      "gi",
    );
    for (const propertyMatch of html.matchAll(propertyPattern)) {
      matchedIDs.add(id);
      collectPatternValues(
        propertyMatch[1] ?? "",
        SCRIPT_TOTAL_PATTERNS,
        values,
      );
    }
  }
  return {
    values: Array.from(values),
    activeContainersAreEmpty:
      matchedIDs.size > 0 &&
      Array.from(matchedIDs).every((id) => emptyElementExists(html, id)),
  };
}

function globalScriptTotals(html: string): number[] {
  const values = new Set<number>();
  collectPatternValues(html, SCRIPT_TOTAL_PATTERNS, values);
  return Array.from(values);
}

function collectPatternValues(
  source: string,
  patterns: RegExp[],
  values: Set<number>,
): void {
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      const value = Number(match[1]);
      if (Number.isSafeInteger(value) && value > 0) {
        values.add(value);
      }
    }
  }
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function emptyElementExists(html: string, id: string): boolean {
  const escapedID = escapeRegExp(id);
  const pattern = new RegExp(
    `<([a-z][\\w:-]*)\\b(?=[^>]*\\bid\\s*=\\s*["']${escapedID}["'])` +
      "[^>]*>\\s*</\\1>",
    "i",
  );
  return pattern.test(html);
}
