import type {ExtractionCandidateEvidence} from "./core.js";
import {
  extractionSourceEvidence,
  type ExtractionSourceEvidence,
} from "./evidence.js";
import type {ExpectedCountEvidence} from "./expected-count.js";
import type {ProgrammaticGalleryEvidence} from "./programmatic-gallery.js";
import type {
  ExtractionQualityReason,
  ExtractionQualityStatus,
} from "./quality.js";
import type {ExtractionVersionSet} from "./version.js";
import {
  extractionIssueOccurrenceKey,
  extractionIssueFingerprint,
  type ExtractionIssueStage,
} from "./issue-contract.js";

const RETENTION_DAYS = 7;
const MAX_ELEMENTS = 120;
const MAX_TEXT_LENGTH = 160;
const MAX_CLASS_TOKENS = 20;
const ALLOWED_SOURCE_ATTRIBUTES = new Set([
  "src",
  "data-src",
  "data-original",
  "data-lazy",
  "data-lazy-src",
  "href",
  "srcset",
]);

export type RetainedElementEvidence = {
  tag: string;
  id: string | null;
  classes: string[];
  text: string | null;
  sources: Array<{
    attribute: string;
    source: ExtractionSourceEvidence;
  }>;
};

export type RetainedExtractionEvidence = {
  schemaVersion: 1;
  status: Extract<ExtractionQualityStatus, "failed" | "needsReview">;
  stage: ExtractionIssueStage;
  source: ExtractionSourceEvidence;
  strategy: string;
  failureReasons: string[];
  qualityReasons: ExtractionQualityReason[];
  templateSignature: string;
  candidateEvidence: ExtractionCandidateEvidence[];
  expectedCountEvidence: ExpectedCountEvidence[];
  programmaticGalleryEvidence: ProgrammaticGalleryEvidence | null;
  structureTokens: string[];
  elements: RetainedElementEvidence[];
  versions: ExtractionVersionSet;
};

export type ExtractionIssueIdentity = {
  fingerprint: string;
  stage: ExtractionIssueStage;
  platform: string;
  strategy: string;
  failureReasons: string[];
  qualityReasons: string[];
  templateSignature: string;
  extractorMajorVersion: string;
};

export function evidenceShouldBeRetained(
  status: ExtractionQualityStatus,
): status is "failed" | "needsReview" {
  return status === "failed" || status === "needsReview";
}

export function evidenceExpiresAt(now = new Date()): Date {
  return new Date(now.getTime() + RETENTION_DAYS * 24 * 60 * 60 * 1000);
}

export function buildRetainedExtractionEvidence(input: {
  status: "failed" | "needsReview";
  stage: ExtractionIssueStage;
  sourceURL: string;
  html?: string | null;
  strategy: string;
  failureReasons?: string[];
  qualityReasons?: ExtractionQualityReason[];
  templateSignature: string;
  candidateEvidence?: ExtractionCandidateEvidence[];
  expectedCountEvidence?: ExpectedCountEvidence[];
  programmaticGalleryEvidence?: ProgrammaticGalleryEvidence | null;
  structureTokens?: string[];
  versions: ExtractionVersionSet;
}): RetainedExtractionEvidence {
  return {
    schemaVersion: 1,
    status: input.status,
    stage: input.stage,
    source: extractionSourceEvidence(input.sourceURL),
    strategy: input.strategy,
    failureReasons: normalizedReasons(input.failureReasons ?? []),
    qualityReasons: Array.from(new Set(input.qualityReasons ?? [])).sort(),
    templateSignature: input.templateSignature,
    candidateEvidence: (input.candidateEvidence ?? []).slice(0, 120),
    expectedCountEvidence: (input.expectedCountEvidence ?? []).slice(0, 20),
    programmaticGalleryEvidence: input.programmaticGalleryEvidence ?? null,
    structureTokens: Array.from(
      new Set(input.structureTokens ?? []),
    ).sort().slice(0, 40),
    elements: input.html === null || input.html === undefined ?
      [] :
      retainedElements(input.html, input.sourceURL),
    versions: input.versions,
  };
}

export function extractionIssueIdentity(
  evidence: RetainedExtractionEvidence,
): ExtractionIssueIdentity {
  const extractorMajorVersion =
    evidence.versions.extractorVersion.split(".")[0] ??
    evidence.versions.extractorVersion;
  const platform = evidence.versions.platformAdapterKey ?? "generic";
  const identity = {
    stage: evidence.stage,
    platform,
    parserStrategy: evidence.strategy,
    failureReasons: normalizedReasons(evidence.failureReasons),
    qualityReasons: normalizedReasons(evidence.qualityReasons),
    templateSignature: evidence.templateSignature,
    extractorMajorVersion,
  };
  return {
    fingerprint: extractionIssueFingerprint({
      stage: identity.stage,
      platform: identity.platform,
      parserStrategy: identity.parserStrategy,
      failureReasons: identity.failureReasons,
      qualityReasons: identity.qualityReasons,
      templateSignature: identity.templateSignature,
      extractorVersion: evidence.versions.extractorVersion,
    }),
    stage: identity.stage,
    platform: identity.platform,
    strategy: identity.parserStrategy,
    failureReasons: identity.failureReasons,
    qualityReasons: identity.qualityReasons,
    templateSignature: identity.templateSignature,
    extractorMajorVersion: identity.extractorMajorVersion,
  };
}

export function extractionEvidenceID(input: {
  jobPath: string;
  generation: number;
  stage: ExtractionIssueStage;
  fingerprint: string;
}): string {
  return extractionIssueOccurrenceKey({
    jobPath: input.jobPath,
    generation: input.generation,
    evidenceID: input.fingerprint,
  });
}

export function extractionEvidenceStoragePath(evidenceID: string): string {
  if (!/^[a-f0-9]{40}$/.test(evidenceID)) {
    throw new Error("evidence ID가 올바르지 않습니다.");
  }
  return `lookbook-extraction-evidence/${evidenceID}.json`;
}

function retainedElements(
  html: string,
  sourceURL: string,
): RetainedElementEvidence[] {
  const result: RetainedElementEvidence[] = [];
  const withoutExecutableContent = html.replace(
    /<(script|style|noscript|template)\b[^>]*>[\s\S]*?<\/\1>/gi,
    "",
  );
  const tagPattern =
    /<(a|img|source|picture|main|article|section|div|ul|ol)\b([^>]*)>([^<]*)/gi;
  for (const match of withoutExecutableContent.matchAll(tagPattern)) {
    if (result.length >= MAX_ELEMENTS) {
      break;
    }
    const tag = String(match[1] ?? "").toLowerCase();
    const attributes = parseAllowedAttributes(String(match[2] ?? ""));
    const sources = sourceAttributes(attributes, sourceURL);
    const id = shortText(attributes.get("id") ?? null, 80);
    const classes = (attributes.get("class") ?? "")
      .split(/\s+/)
      .map((value) => value.trim().toLowerCase())
      .filter((value) => /^[a-z0-9_-]{1,80}$/.test(value))
      .slice(0, MAX_CLASS_TOKENS);
    const text = tag === "img" || tag === "source" ?
      shortText(attributes.get("alt") ?? null, MAX_TEXT_LENGTH) :
      shortText(match[3] ?? null, MAX_TEXT_LENGTH);
    if (
      sources.length === 0 &&
      id === null &&
      classes.length === 0 &&
      text === null
    ) {
      continue;
    }
    result.push({tag, id, classes, text, sources});
  }
  return result;
}

function parseAllowedAttributes(raw: string): Map<string, string> {
  const result = new Map<string, string>();
  const pattern = /([a-zA-Z0-9_-]+)\s*=\s*(["'])(.*?)\2/g;
  for (const match of raw.matchAll(pattern)) {
    const name = String(match[1] ?? "").toLowerCase();
    if (
      ALLOWED_SOURCE_ATTRIBUTES.has(name) ||
      name === "id" ||
      name === "class" ||
      name === "alt"
    ) {
      result.set(name, String(match[3] ?? ""));
    }
  }
  return result;
}

function sourceAttributes(
  attributes: Map<string, string>,
  sourceURL: string,
): RetainedElementEvidence["sources"] {
  const result: RetainedElementEvidence["sources"] = [];
  for (const [attribute, raw] of attributes) {
    if (!ALLOWED_SOURCE_ATTRIBUTES.has(attribute)) {
      continue;
    }
    const values = attribute === "srcset" ?
      raw.split(",").map((item) => item.trim().split(/\s+/)[0] ?? "") :
      [raw];
    for (const value of values) {
      try {
        result.push({
          attribute,
          source: extractionSourceEvidence(
            new URL(value, sourceURL).toString(),
          ),
        });
      } catch {
        // 실행 가능한 template 문자열과 잘못된 URL은 evidence에서 제외한다.
      }
    }
  }
  return result.slice(0, 20);
}

function normalizedReasons(values: string[]): string[] {
  return Array.from(
    new Set(values.map((value) => value.trim()).filter(Boolean)),
  ).sort();
}

function shortText(value: string | null, maxLength: number): string | null {
  const normalized = value
    ?.replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim() ?? "";
  return normalized.length === 0 ? null : normalized.slice(0, maxLength);
}
