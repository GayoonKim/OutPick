/* eslint-disable require-jsdoc, max-len */
import {
  canonicalDiscoveryURL,
  seasonDiscoveryRequestFingerprint,
  SEASON_DISCOVERY_CONTRACT_REVISION,
  SEASON_DISCOVERY_EXTRACTOR_VERSION,
  SEASON_DISCOVERY_SCHEMA_VERSION,
  type SeasonDiscoveryFingerprintInput,
} from "../../shared/seasonDiscoveryCreation.js";

export {
  canonicalDiscoveryURL,
  seasonDiscoveryRequestFingerprint,
  SEASON_DISCOVERY_CONTRACT_REVISION,
  SEASON_DISCOVERY_EXTRACTOR_VERSION,
  SEASON_DISCOVERY_SCHEMA_VERSION,
  type SeasonDiscoveryFingerprintInput,
};

export type SeasonDiscoveryStatus =
  | "queued"
  | "dispatching"
  | "running"
  | "succeeded"
  | "awaitingReview"
  | "correctionRequired"
  | "failed"
  | "cancelled"
  | "superseded";

export type SeasonDiscoveryRecommendedAction =
  | "retry"
  | "updateSourceURL"
  | "reviewCandidates"
  | "waitForExtractorFix"
  | "reanalyzeWithNewVersion"
  | "cancel"
  | "none";

export type SeasonDiscoveryImprovementDisposition =
  | "notEligible"
  | "requestable"
  | "requested"
  | "ready";

export function seasonDiscoveryBlockedRevision(input: {
  blockedRevision: unknown;
  extractionContractRevision: unknown;
  currentRevision: number;
}): number {
  if (Number.isInteger(input.blockedRevision)) {
    return Number(input.blockedRevision);
  }
  if (Number.isInteger(input.extractionContractRevision)) {
    return Number(input.extractionContractRevision);
  }
  return input.currentRevision;
}

export function normalizedSeasonDiscoveryIssueFingerprint(
  value: unknown
): string | null {
  if (typeof value !== "string" || !/^[a-f0-9]{40}(?:[a-f0-9]{24})?$/.test(value)) {
    return null;
  }
  return value.slice(0, 40);
}

export function seasonDiscoveryImprovementDisposition(input: {
  status: SeasonDiscoveryStatus;
  improvementRequested: boolean;
  blockedRevision: number;
  availableRevision: number | null;
  resolvedByJobID?: string | null;
}): SeasonDiscoveryImprovementDisposition {
  if (input.status !== "correctionRequired" || input.resolvedByJobID) {
    return "notEligible";
  }
  if (!input.improvementRequested) return "requestable";
  if (input.availableRevision !== null &&
      input.availableRevision > input.blockedRevision) return "ready";
  return "requested";
}

const ACTIVE_STATUSES = new Set<SeasonDiscoveryStatus>([
  "queued", "dispatching", "running",
]);
const ACTION_REQUIRED_STATUSES = new Set<SeasonDiscoveryStatus>([
  "awaitingReview", "correctionRequired",
]);
const TERMINAL_STATUSES = new Set<SeasonDiscoveryStatus>([
  "succeeded", "failed", "cancelled", "superseded",
]);

export function isActiveSeasonDiscoveryStatus(
  status: SeasonDiscoveryStatus
): boolean {
  return ACTIVE_STATUSES.has(status);
}

export function isActionRequiredSeasonDiscoveryStatus(
  status: SeasonDiscoveryStatus
): boolean {
  return ACTION_REQUIRED_STATUSES.has(status);
}

export function isTerminalSeasonDiscoveryStatus(
  status: SeasonDiscoveryStatus
): boolean {
  return TERMINAL_STATUSES.has(status);
}

export function seasonDiscoveryExpiresAt(
  status: SeasonDiscoveryStatus,
  completedAt: Date
): Date | null {
  if (isActiveSeasonDiscoveryStatus(status) ||
      isActionRequiredSeasonDiscoveryStatus(status)) {
    return null;
  }
  const days = status === "failed" ? 60 : 30;
  return new Date(completedAt.getTime() + days * 24 * 60 * 60 * 1000);
}

export function seasonDiscoveryRecommendedAction(input: {
  status: SeasonDiscoveryStatus;
  errorCode?: string | null;
  retryable?: boolean;
}): SeasonDiscoveryRecommendedAction {
  if (input.status === "awaitingReview") return "reviewCandidates";
  if (input.status === "correctionRequired") return "waitForExtractorFix";
  if (input.status !== "failed") return "none";
  if (input.retryable) return "retry";
  if (input.errorCode === "invalid_source_url" ||
      input.errorCode === "source_not_found") return "updateSourceURL";
  return "cancel";
}

export function deterministicSeasonDiscoveryTaskID(
  brandID: string,
  jobID: string,
  dispatchGeneration: number
): string {
  const encoded = Buffer
    .from(`${brandID}:${jobID}:${dispatchGeneration}`)
    .toString("base64url");
  return `season-discovery-${encoded}`.slice(0, 500);
}

export function canRecordSeasonDiscoveryDispatch(input: {
  status: unknown;
  generation: unknown;
  dispatchGeneration: unknown;
  expectedGeneration: number;
  expectedDispatchGeneration: number;
}): boolean {
  return input.status === "queued" &&
    input.generation === input.expectedGeneration &&
    input.dispatchGeneration === input.expectedDispatchGeneration;
}

export function isCurrentPublishedSeasonDiscoverySnapshot(input: {
  publishedJobID: unknown;
  publishedGeneration: unknown;
  publishedSnapshotHash: unknown;
  publishedExpiresAtMillis: number | null;
  jobID: string;
  jobGeneration: unknown;
  jobSnapshotHash: unknown;
  jobStatus: unknown;
  candidateGeneration: unknown;
  candidateSnapshotHash: unknown;
  candidateResolution: unknown;
  expectedGeneration: number;
  expectedSnapshotHash: string;
  nowMillis: number;
}): boolean {
  return input.publishedJobID === input.jobID &&
    input.publishedGeneration === input.expectedGeneration &&
    input.publishedSnapshotHash === input.expectedSnapshotHash &&
    input.jobGeneration === input.expectedGeneration &&
    input.jobSnapshotHash === input.expectedSnapshotHash &&
    (input.jobStatus === "succeeded" || input.jobStatus === "awaitingReview") &&
    input.candidateGeneration === input.expectedGeneration &&
    input.candidateSnapshotHash === input.expectedSnapshotHash &&
    input.candidateResolution === "newSeason" &&
    (input.publishedExpiresAtMillis === null ||
      input.publishedExpiresAtMillis > input.nowMillis);
}

export function isSeasonAvailableForDiscoveryReview(
  data: Record<string, unknown> | undefined
): boolean {
  if (!data) return false;
  return data.deletionStatus === undefined || data.deletionStatus === "active";
}
