import {createHash} from "node:crypto";

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
  stage: string;
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
  stage: string;
  platform: string;
  strategy: string;
  failureReasons: string[];
  qualityReasons: string[];
  templateSignature: string;
  extractorMajorVersion: string;
};

export type ExtractionIssueClusterState = {
  occurrenceCount: number;
  affectedDomains: string[];
  affectedDomainCount: number;
  sampleEvidenceIDs: string[];
  status: string;
  recurrenceCount: number;
  isRecurrence: boolean;
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
  stage: string;
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
    strategy: evidence.strategy,
    failureReasons: normalizedReasons(evidence.failureReasons),
    qualityReasons: normalizedReasons(evidence.qualityReasons),
    templateSignature: evidence.templateSignature,
    extractorMajorVersion,
  };
  return {
    fingerprint: createHash("sha256")
      .update(JSON.stringify(identity))
      .digest("hex")
      .slice(0, 40),
    ...identity,
  };
}

export function extractionEvidenceID(input: {
  brandID: string;
  jobID: string;
  dispatchGeneration: number;
  stage: string;
  fingerprint: string;
}): string {
  return createHash("sha256")
    .update([
      input.brandID,
      input.jobID,
      input.dispatchGeneration,
      input.stage,
      input.fingerprint,
    ].join(":"))
    .digest("hex")
    .slice(0, 40);
}

export function extractionEvidenceStoragePath(evidenceID: string): string {
  if (!/^[a-f0-9]{40}$/.test(evidenceID)) {
    throw new Error("evidence ID가 올바르지 않습니다.");
  }
  return `lookbook-extraction-evidence/${evidenceID}.json`;
}

export function versionIsAtLeast(current: string, fixed: string): boolean {
  const currentParts = numericVersion(current);
  const fixedParts = numericVersion(fixed);
  for (let index = 0; index < 3; index += 1) {
    const currentPart = currentParts[index] ?? 0;
    const fixedPart = fixedParts[index] ?? 0;
    if (currentPart !== fixedPart) {
      return currentPart > fixedPart;
    }
  }
  return true;
}

export function nextExtractionIssueClusterState(input: {
  previous?: {
    occurrenceCount?: unknown;
    affectedDomains?: unknown;
    sampleEvidenceIDs?: unknown;
    status?: unknown;
    recurrenceCount?: unknown;
    fixedInExtractorVersion?: unknown;
  };
  sourceHost: string;
  evidenceID: string;
  extractorVersion: string;
}): ExtractionIssueClusterState {
  const previous = input.previous ?? {};
  const affectedDomains = Array.from(new Set([
    ...stringValues(previous.affectedDomains),
    input.sourceHost.toLowerCase(),
  ])).sort().slice(0, 200);
  const sampleEvidenceIDs = Array.from(new Set([
    ...stringValues(previous.sampleEvidenceIDs),
    input.evidenceID,
  ])).slice(-20);
  const fixedVersion = typeof previous.fixedInExtractorVersion === "string" ?
    previous.fixedInExtractorVersion.trim() :
    "";
  const isRecurrence = fixedVersion.length > 0 &&
    versionIsAtLeast(input.extractorVersion, fixedVersion);
  return {
    occurrenceCount: nonNegativeNumber(previous.occurrenceCount) + 1,
    affectedDomains,
    affectedDomainCount: affectedDomains.length,
    sampleEvidenceIDs,
    status: isRecurrence ? "open" : stringOr(previous.status, "open"),
    recurrenceCount: nonNegativeNumber(previous.recurrenceCount) +
      (isRecurrence ? 1 : 0),
    isRecurrence,
  };
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

function numericVersion(value: string): number[] {
  return value.split(".").slice(0, 3).map((part) => {
    const parsed = Number.parseInt(part, 10);
    return Number.isFinite(parsed) ? parsed : 0;
  });
}

function stringValues(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function stringOr(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    fallback;
}

function nonNegativeNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.max(0, Math.floor(value)) :
    0;
}
