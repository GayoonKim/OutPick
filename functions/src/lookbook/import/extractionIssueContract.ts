/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";

export const EXTRACTION_ISSUE_STAGES = [
  "seasonDiscovery",
  "seasonImageImport",
] as const;

export type ExtractionIssueStage =
  typeof EXTRACTION_ISSUE_STAGES[number];

export const EXTRACTION_FAILURE_DISPOSITIONS = [
  "extractionLogicInsufficient",
  "transientInfrastructure",
  "invalidInput",
  "permanentAccess",
  "authenticationRequired",
  "cancelled",
  "staleGeneration",
  "identityReview",
] as const;

export type ExtractionFailureDisposition =
  typeof EXTRACTION_FAILURE_DISPOSITIONS[number];

export const EXTRACTION_ISSUE_STATUSES = [
  "open",
  "inProgress",
  "needsGroundTruth",
  "fixed",
  "verified",
  "wontFix",
] as const;

export type ExtractionIssueStatus =
  typeof EXTRACTION_ISSUE_STATUSES[number];

export type ExtractionIssueAction =
  | "startProcessing"
  | "markNeedsGroundTruth"
  | "recordGroundTruthAndResume"
  | "reopen"
  | "markWontFix"
  | "markFixed"
  | "markVerified";

export type ExtractionRuntimeVersionKind = "contract" | "extractor";

const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;
const OCCURRENCE_RETENTION_DAYS = 7;
const TERMINAL_RETENTION_DAYS = 60;
const FINGERPRINT_PATTERN = /^[a-f0-9]{40}$/;
const SEMANTIC_VERSION_PATTERN =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

const ACTION_TRANSITIONS: Record<
  ExtractionIssueAction,
  Partial<Record<ExtractionIssueStatus, ExtractionIssueStatus>>
> = {
  startProcessing: {open: "inProgress"},
  markNeedsGroundTruth: {inProgress: "needsGroundTruth"},
  recordGroundTruthAndResume: {needsGroundTruth: "inProgress"},
  reopen: {
    needsGroundTruth: "open",
    verified: "open",
    wontFix: "open",
  },
  markWontFix: {
    open: "wontFix",
    inProgress: "wontFix",
    needsGroundTruth: "wontFix",
  },
  markFixed: {inProgress: "fixed"},
  markVerified: {fixed: "verified"},
};

export function isExtractionIssueEligible(
  disposition: unknown
): disposition is "extractionLogicInsufficient" {
  return disposition === "extractionLogicInsufficient";
}

export function extractionIssueFingerprint(input: {
  stage: ExtractionIssueStage;
  platform: string | null;
  parserStrategy: string;
  failureReasons: string[];
  qualityReasons: string[];
  templateSignature: string;
  extractorVersion: string;
}): string {
  const identity = normalizedExtractionIssueIdentity(input);
  return createHash("sha256")
    .update(JSON.stringify(identity))
    .digest("hex")
    .slice(0, 40);
}

export function extractionIssueOccurrenceKey(input: {
  jobPath: string;
  generation: number;
  evidenceID: string;
}): string {
  const identity = {
    jobPath: requiredJobPath(input.jobPath),
    generation: requiredNonNegativeInteger(input.generation, "generation"),
    evidenceID: requiredFingerprint(input.evidenceID, "evidenceID"),
  };
  return createHash("sha256")
    .update(JSON.stringify(identity))
    .digest("hex")
    .slice(0, 40);
}

export function encodeExtractionRuntimeVersion(input: {
  kind: ExtractionRuntimeVersionKind;
  value: number | string;
}): string {
  if (input.kind === "contract") {
    return `contract:${requiredNonNegativeInteger(
      input.value,
      "contract revision"
    )}`;
  }
  const version = requiredSemanticVersion(input.value, "extractor version");
  return `extractor:${version}`;
}

export function encodeExtractionRuntimeVersionForStage(input: {
  stage: ExtractionIssueStage;
  value: number | string;
}): string {
  return encodeExtractionRuntimeVersion({
    kind: extractionRuntimeVersionKind(input.stage),
    value: input.value,
  });
}

export function extractionRuntimeVersionMatchesStage(
  stage: ExtractionIssueStage,
  version: string
): boolean {
  return parsedRuntimeVersion(version)?.kind ===
    extractionRuntimeVersionKind(stage);
}

export function compareExtractionRuntimeVersions(
  lhs: string,
  rhs: string
): -1 | 0 | 1 | null {
  const left = parsedRuntimeVersion(lhs);
  const right = parsedRuntimeVersion(rhs);
  if (left === null || right === null || left.kind !== right.kind) {
    return null;
  }
  const length = Math.max(left.parts.length, right.parts.length);
  for (let index = 0; index < length; index += 1) {
    const leftPart = left.parts[index] ?? 0;
    const rightPart = right.parts[index] ?? 0;
    if (leftPart !== rightPart) {
      return leftPart > rightPart ? 1 : -1;
    }
  }
  return 0;
}

export function isExtractionFixRetryEligible(input: {
  issueStatus: unknown;
  blockedRuntimeVersion: unknown;
  retryAvailableRuntimeVersion: unknown;
  stage: ExtractionIssueStage;
}): boolean {
  const prefix = input.stage === "seasonDiscovery" ? "contract:" : "extractor:";
  return input.issueStatus === "fixed" &&
    typeof input.blockedRuntimeVersion === "string" &&
    input.blockedRuntimeVersion.startsWith(prefix) &&
    typeof input.retryAvailableRuntimeVersion === "string" &&
    input.retryAvailableRuntimeVersion.startsWith(prefix) &&
    compareExtractionRuntimeVersions(
      input.blockedRuntimeVersion,
      input.retryAvailableRuntimeVersion
    ) === -1;
}

export function extractionRuntimeVersionIsAtLeast(
  current: string,
  fixed: string
): boolean {
  const comparison = compareExtractionRuntimeVersions(current, fixed);
  return comparison !== null && comparison >= 0;
}

export function transitionExtractionIssueState(input: {
  status: ExtractionIssueStatus;
  stateVersion: number;
  expectedStateVersion: number;
  action: ExtractionIssueAction;
}): {status: ExtractionIssueStatus; stateVersion: number} {
  const stateVersion = requiredNonNegativeInteger(
    input.stateVersion,
    "stateVersion"
  );
  const expectedStateVersion = requiredNonNegativeInteger(
    input.expectedStateVersion,
    "expectedStateVersion"
  );
  if (stateVersion !== expectedStateVersion) {
    throw new Error("extraction issue stateVersion 충돌입니다.");
  }
  const nextStatus = ACTION_TRANSITIONS[input.action][input.status];
  if (nextStatus === undefined) {
    throw new Error("허용되지 않은 extraction issue 상태 전이입니다.");
  }
  return {status: nextStatus, stateVersion: stateVersion + 1};
}

export function resolveExtractionIssueOccurrence(input: {
  status: ExtractionIssueStatus;
  stateVersion: number;
  occurrenceRuntimeVersion: string;
  fixedRuntimeVersion?: string | null;
}): {
  status: ExtractionIssueStatus;
  stateVersion: number;
  isRecurrence: boolean;
} {
  const stateVersion = requiredNonNegativeInteger(
    input.stateVersion,
    "stateVersion"
  );
  const shouldReopen = input.status === "wontFix" ||
    (
      (input.status === "fixed" || input.status === "verified") &&
      typeof input.fixedRuntimeVersion === "string" &&
      extractionRuntimeVersionIsAtLeast(
        input.occurrenceRuntimeVersion,
        input.fixedRuntimeVersion
      )
    );
  if (!shouldReopen) {
    return {status: input.status, stateVersion, isRecurrence: false};
  }
  return {status: "open", stateVersion: stateVersion + 1, isRecurrence: true};
}

export function occurrenceEvidenceExpiresAt(now = new Date()): Date {
  return dateAfterDays(now, OCCURRENCE_RETENTION_DAYS);
}

export function extractionIssueExpiresAt(
  status: ExtractionIssueStatus,
  now = new Date()
): Date | null {
  return status === "verified" || status === "wontFix" ?
    dateAfterDays(now, TERMINAL_RETENTION_DAYS) :
    null;
}

export function terminalExtractionJobExpiresAt(now = new Date()): Date {
  return dateAfterDays(now, TERMINAL_RETENTION_DAYS);
}

function normalizedExtractionIssueIdentity(input: {
  stage: ExtractionIssueStage;
  platform: string | null;
  parserStrategy: string;
  failureReasons: string[];
  qualityReasons: string[];
  templateSignature: string;
  extractorVersion: string;
}): {
  stage: ExtractionIssueStage;
  platform: string;
  parserStrategy: string;
  failureReasons: string[];
  qualityReasons: string[];
  templateSignature: string;
  extractorMajorVersion: string;
} {
  if (!EXTRACTION_ISSUE_STAGES.includes(input.stage)) {
    throw new Error("extraction issue stage가 올바르지 않습니다.");
  }
  return {
    stage: input.stage,
    platform: optionalToken(input.platform)?.toLowerCase() ?? "generic",
    parserStrategy: requiredToken(input.parserStrategy, "parserStrategy"),
    failureReasons: normalizedReasons(input.failureReasons),
    qualityReasons: normalizedReasons(input.qualityReasons),
    templateSignature: requiredToken(
      input.templateSignature,
      "templateSignature"
    ),
    extractorMajorVersion: requiredSemanticVersion(
      input.extractorVersion,
      "extractorVersion"
    ).split(".")[0] as string,
  };
}

function extractionRuntimeVersionKind(
  stage: ExtractionIssueStage
): ExtractionRuntimeVersionKind {
  if (stage === "seasonDiscovery") {
    return "contract";
  }
  if (stage === "seasonImageImport") {
    return "extractor";
  }
  throw new Error("extraction issue stage가 올바르지 않습니다.");
}

function parsedRuntimeVersion(value: string): {
  kind: ExtractionRuntimeVersionKind;
  parts: number[];
} | null {
  const contractMatch = /^contract:(0|[1-9]\d*)$/.exec(value);
  if (contractMatch) {
    return {kind: "contract", parts: [Number(contractMatch[1])]};
  }
  const extractorMatch =
    /^extractor:(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(value);
  if (extractorMatch) {
    return {
      kind: "extractor",
      parts: extractorMatch.slice(1).map(Number),
    };
  }
  return null;
}

function normalizedReasons(values: string[]): string[] {
  if (!Array.isArray(values)) {
    throw new Error("extraction issue reason 목록이 올바르지 않습니다.");
  }
  return Array.from(new Set(values.map((value) =>
    requiredToken(value, "reason")
  ))).sort();
}

function requiredJobPath(value: unknown): string {
  const result = requiredToken(value, "jobPath");
  if (!result.includes("/") || result.startsWith("/") || result.endsWith("/")) {
    throw new Error("jobPath가 올바르지 않습니다.");
  }
  return result;
}

function requiredFingerprint(value: unknown, name: string): string {
  if (typeof value !== "string" || !FINGERPRINT_PATTERN.test(value)) {
    throw new Error(`${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

function requiredSemanticVersion(value: unknown, name: string): string {
  if (typeof value !== "string" || !SEMANTIC_VERSION_PATTERN.test(value)) {
    throw new Error(`${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

function requiredNonNegativeInteger(value: unknown, name: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error(`${name} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

function requiredToken(value: unknown, name: string): string {
  if (typeof value !== "string") {
    throw new Error(`${name} 값이 올바르지 않습니다.`);
  }
  const result = value.trim();
  if (result.length === 0 || result.length > 200) {
    throw new Error(`${name} 값이 올바르지 않습니다.`);
  }
  return result;
}

function optionalToken(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  return requiredToken(value, "platform");
}

function dateAfterDays(now: Date, days: number): Date {
  if (!Number.isFinite(now.getTime())) {
    throw new Error("기준 시각이 올바르지 않습니다.");
  }
  return new Date(now.getTime() + days * DAY_MILLISECONDS);
}
