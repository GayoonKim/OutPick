import type {ExtractionVersionSet} from "./version.js";
import type {RetainedExtractionEvidence} from "./retained-evidence.js";
import {
  EXTRACTION_ISSUE_STATUSES,
  resolveExtractionIssueOccurrence,
  type ExtractionFailureDisposition,
  type ExtractionIssueStatus,
} from "./issue-contract.js";

export type ExtractionAdapterIdentity = {
  scope: "generic" | "platform" | "domain";
  key: string;
};

export type RepresentativeEvidenceScore = {
  schemaVersion: number;
  hasExpectedCount: number;
  candidateEvidenceCount: number;
  structureTokenCount: number;
  elementCount: number;
};

export function extractionAdapterIdentity(
  versions: ExtractionVersionSet,
): ExtractionAdapterIdentity {
  if (versions.domainAdapterKey !== null) {
    return {scope: "domain", key: versions.domainAdapterKey};
  }
  if (versions.platformAdapterKey !== null) {
    return {scope: "platform", key: versions.platformAdapterKey};
  }
  return {scope: "generic", key: "generic"};
}

export function imageExtractionIssueDisposition(
  evidence: RetainedExtractionEvidence,
): ExtractionFailureDisposition {
  const positiveReasons = new Set([
    "no_candidates",
    "expected_count_mismatch",
    "large_rendered_delta_without_expected_evidence",
    "raw_candidate_drop",
  ]);
  if (
    evidence.failureReasons.includes("parse_failed") ||
    evidence.qualityReasons.some((reason) => positiveReasons.has(reason))
  ) {
    return "extractionLogicInsufficient";
  }
  if (
    evidence.failureReasons.includes("retry_exhausted") ||
    evidence.qualityReasons.includes("content_hash_incomplete")
  ) {
    return "transientInfrastructure";
  }
  return "identityReview";
}

export function seasonDiscoveryIssueDisposition(input: {
  failureReasons: string[];
  unresolvedExpansion: boolean;
}): ExtractionFailureDisposition {
  if (
    input.failureReasons.includes("no_candidates_found") ||
    input.failureReasons.includes("low_confidence_candidates") ||
    input.unresolvedExpansion
  ) {
    return "extractionLogicInsufficient";
  }
  if (
    input.failureReasons.includes("worker_timeout") ||
    input.failureReasons.includes("worker_failed") ||
    input.failureReasons.includes("archive_url_fetch_failed")
  ) {
    return "transientInfrastructure";
  }
  if (input.failureReasons.includes("archive_url_missing")) {
    return "invalidInput";
  }
  return "identityReview";
}

export function representativeEvidenceScore(
  evidence: RetainedExtractionEvidence,
): RepresentativeEvidenceScore {
  return {
    schemaVersion: evidence.schemaVersion,
    hasExpectedCount: evidence.expectedCountEvidence.length > 0 ? 1 : 0,
    candidateEvidenceCount: evidence.candidateEvidence.length,
    structureTokenCount: evidence.structureTokens.length,
    elementCount: evidence.elements.length,
  };
}

export function shouldReplaceRepresentativeEvidence(input: {
  status: unknown;
  previousScore: unknown;
  candidateScore: RepresentativeEvidenceScore;
}): boolean {
  if (input.status !== "ready") {
    return true;
  }
  const previous = parsedRepresentativeScore(input.previousScore);
  if (previous === null) {
    return true;
  }
  const keys: Array<keyof RepresentativeEvidenceScore> = [
    "schemaVersion",
    "hasExpectedCount",
    "candidateEvidenceCount",
    "structureTokenCount",
    "elementCount",
  ];
  for (const key of keys) {
    if (input.candidateScore[key] !== previous[key]) {
      return input.candidateScore[key] > previous[key];
    }
  }
  return false;
}

export function nextIssueClusterOccurrence(input: {
  previous: Record<string, unknown>;
  runtimeVersion: string;
}): {
  status: ExtractionIssueStatus;
  stateVersion: number;
  occurrenceCount: number;
  recurrenceCount: number;
  isRecurrence: boolean;
  clearExpiresAt: boolean;
} {
  const previousStatus = validStatus(input.previous.status) ?? "open";
  const previousStateVersion = nonNegativeInteger(
    input.previous.stateVersion,
    1,
  );
  const resolution = resolveExtractionIssueOccurrence({
    status: previousStatus,
    stateVersion: previousStateVersion,
    occurrenceRuntimeVersion: input.runtimeVersion,
    fixedRuntimeVersion: optionalString(input.previous.fixedRuntimeVersion),
  });
  return {
    ...resolution,
    occurrenceCount: nonNegativeInteger(input.previous.occurrenceCount, 0) + 1,
    recurrenceCount: nonNegativeInteger(input.previous.recurrenceCount, 0) +
      (resolution.isRecurrence ? 1 : 0),
    clearExpiresAt: resolution.isRecurrence,
  };
}

function parsedRepresentativeScore(
  value: unknown,
): RepresentativeEvidenceScore | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  const fields: Array<keyof RepresentativeEvidenceScore> = [
    "schemaVersion",
    "hasExpectedCount",
    "candidateEvidenceCount",
    "structureTokenCount",
    "elementCount",
  ];
  if (fields.some((field) => !Number.isSafeInteger(record[field]) ||
      Number(record[field]) < 0)) {
    return null;
  }
  return {
    schemaVersion: Number(record.schemaVersion),
    hasExpectedCount: Number(record.hasExpectedCount),
    candidateEvidenceCount: Number(record.candidateEvidenceCount),
    structureTokenCount: Number(record.structureTokenCount),
    elementCount: Number(record.elementCount),
  };
}

function validStatus(value: unknown): ExtractionIssueStatus | null {
  return typeof value === "string" &&
    EXTRACTION_ISSUE_STATUSES.includes(value as ExtractionIssueStatus) ?
    value as ExtractionIssueStatus :
    null;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function nonNegativeInteger(value: unknown, fallback: number): number {
  return Number.isSafeInteger(value) && Number(value) >= 0 ?
    Number(value) :
    fallback;
}
