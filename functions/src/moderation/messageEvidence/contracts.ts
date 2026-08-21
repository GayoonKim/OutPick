/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";

export const MESSAGE_EVIDENCE_CONTRACT_VERSION = 1;
export const MESSAGE_GLOBAL_VISIBILITY_WINDOW_MILLIS = 24 * 60 * 60 * 1000;
export const MESSAGE_AUTHOR_PATTERN_WINDOW_MILLIS = 7 * 24 * 60 * 60 * 1000;
export const MESSAGE_SANCTION_APPEAL_RETENTION_MILLIS = 30 * 24 * 60 * 60 * 1000;

export type MessageReviewState = "open" | "inReview" | "resolved" | "dismissed";
export type MessageQueueClass = "holding" | "reviewRequired" | "urgent";
export type MessageVisibilityState = "visible" | "hiddenPendingReview" | "deleted";
export type MessageReportStatus =
  "processing" | "accepted" | "alreadyReported" | "failed" | "messageAlreadyDeleted";
export type MessageEvidenceState =
  "copyPending" | "copying" | "available" | "cleanupPending" |
  "deleting" | "deleted" | "failed";
export type MessageEvidencePreparationState =
  "copyPending" | "copying" | "available" | "failed";
export type MessageEvidenceJobState =
  "pending" | "processing" | "retryPending" | "succeeded" | "failed";
export type MessageEvidenceCleanupJobState =
  "awaitingEvidence" | MessageEvidenceJobState;
export type MessageGuardWinner = "reportFirst" | "deleteFirst";
export type MessageReportPriority = "urgent" | "general";
export type MessageReportReason =
  "harassment" | "hate" | "sexual" | "spam" |
  "privacy" | "illegalDangerous" | "other";

export type MessageEvidenceRetentionClass =
  "reviewOpen" | "deleteAfterDecision" | "sanctionAppeal30Days" |
  "appealOpen" | "legalHold";
export type MessageEvidenceDecision =
  "dismissed" | "contentDeleted" | "warningOnly" |
  "temporaryRestriction" | "permanentSuspension";
export type MessageEvidenceAppealState = "none" | "open" | "resolved";

type CanonicalIDPart = string | number;

function canonicalMessageEvidenceID(
  domain: string,
  parts: CanonicalIDPart[],
): string {
  const canonicalTuple = JSON.stringify([
    "outpick",
    domain,
    MESSAGE_EVIDENCE_CONTRACT_VERSION,
    ...parts,
  ]);
  return createHash("sha256").update(canonicalTuple).digest("hex");
}

function assertNonNegativeInteger(value: number, field: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative safe integer`);
  }
}

export function messageIncidentID(roomID: string, messageID: string): string {
  return canonicalMessageEvidenceID("message-incident", [roomID, messageID]);
}

export function messageReviewRevisionID(reviewRevision: number): string {
  assertNonNegativeInteger(reviewRevision, "reviewRevision");
  return `r${reviewRevision}`;
}

export function messageReporterID(
  reporterModerationPrincipalID: string,
): string {
  return canonicalMessageEvidenceID(
    "message-reporter",
    [reporterModerationPrincipalID],
  );
}

export function messageReportPreparationID(input: {
  incidentID: string;
  reviewRevision: number;
  reporterModerationPrincipalID: string;
}): string {
  assertNonNegativeInteger(input.reviewRevision, "reviewRevision");
  return canonicalMessageEvidenceID("message-report-preparation", [
    input.incidentID,
    input.reviewRevision,
    input.reporterModerationPrincipalID,
  ]);
}

export function messageReportSubmissionID(input: {
  incidentID: string;
  reviewRevision: number;
  reporterModerationPrincipalID: string;
  clientRequestID: string;
}): string {
  assertNonNegativeInteger(input.reviewRevision, "reviewRevision");
  return canonicalMessageEvidenceID("message-report-submission", [
    input.incidentID,
    input.reviewRevision,
    input.reporterModerationPrincipalID,
    input.clientRequestID,
  ]);
}

export function messageEvidenceBundleID(
  incidentID: string,
  reviewRevision: number,
): string {
  assertNonNegativeInteger(reviewRevision, "reviewRevision");
  return canonicalMessageEvidenceID(
    "message-evidence-bundle",
    [incidentID, reviewRevision],
  );
}

export function messageGuardID(incidentID: string): string {
  return incidentID;
}

export function messageEvidenceCopyJobID(bundleID: string): string {
  return canonicalMessageEvidenceID("message-evidence-copy-job", [bundleID]);
}

export function messageEvidenceCleanupJobID(bundleID: string): string {
  return canonicalMessageEvidenceID("message-evidence-cleanup-job", [bundleID]);
}

export function nextMessageReviewRevision(input: {
  exists: boolean;
  reviewState: MessageReviewState;
  reviewRevision: number;
}): number {
  assertNonNegativeInteger(input.reviewRevision, "reviewRevision");
  if (!input.exists) return 0;
  return input.reviewState === "resolved" || input.reviewState === "dismissed" ?
    input.reviewRevision + 1 : input.reviewRevision;
}

export function messageReportStatusForEvidence(
  evidenceState: MessageEvidencePreparationState,
): "processing" | "accepted" | "failed" {
  if (evidenceState === "available") return "accepted";
  if (evidenceState === "failed") return "failed";
  return "processing";
}

export function createsAcceptedMessageReportEffects(
  status: MessageReportStatus,
): boolean {
  return status === "accepted";
}

export function isUrgentMessageReportReason(
  reason: MessageReportReason,
): boolean {
  return reason === "sexual" || reason === "privacy" ||
    reason === "illegalDangerous";
}

const MESSAGE_QUEUE_RANK: Record<MessageQueueClass, number> = {
  holding: 0,
  reviewRequired: 1,
  urgent: 2,
};

export function nextMessageQueueClass(input: {
  currentQueueClass: MessageQueueClass | null;
  reason: MessageReportReason;
  distinctAcceptedReporterCount: number;
}): MessageQueueClass {
  assertNonNegativeInteger(
    input.distinctAcceptedReporterCount,
    "distinctAcceptedReporterCount",
  );
  const candidate: MessageQueueClass = isUrgentMessageReportReason(input.reason) ?
    "urgent" : input.distinctAcceptedReporterCount >= 2 ?
      "reviewRequired" : "holding";
  if (input.currentQueueClass === null) return candidate;
  return MESSAGE_QUEUE_RANK[input.currentQueueClass] >= MESSAGE_QUEUE_RANK[candidate] ?
    input.currentQueueClass : candidate;
}

export type MessageReporterSignal = {
  reporterModerationPrincipalID: string;
  priority: MessageReportPriority;
  receivedAt: Date;
};

export function messageGlobalVisibilityEvaluation(
  signals: MessageReporterSignal[],
  now: Date,
): {
  urgentDistinctReporterCount: number;
  totalDistinctReporterCount: number;
  shouldHide: boolean;
} {
  const cutoff = now.getTime() - MESSAGE_GLOBAL_VISIBILITY_WINDOW_MILLIS;
  const reporters = new Map<string, boolean>();
  for (const signal of signals) {
    const receivedAt = signal.receivedAt.getTime();
    if (receivedAt < cutoff || receivedAt > now.getTime()) continue;
    const wasUrgent = reporters.get(signal.reporterModerationPrincipalID) ?? false;
    reporters.set(
      signal.reporterModerationPrincipalID,
      wasUrgent || signal.priority === "urgent",
    );
  }
  const urgentDistinctReporterCount = [...reporters.values()]
    .filter((urgent) => urgent).length;
  const totalDistinctReporterCount = reporters.size;
  return {
    urgentDistinctReporterCount,
    totalDistinctReporterCount,
    shouldHide: urgentDistinctReporterCount >= 2 || totalDistinctReporterCount >= 3,
  };
}

export type MessageAuthorPatternMarker = {
  id: string;
  lastReportedAt: Date;
};

function recentDistinctMarkerTimes(
  markers: MessageAuthorPatternMarker[],
  now: Date,
): number[] {
  const cutoff = now.getTime() - MESSAGE_AUTHOR_PATTERN_WINDOW_MILLIS;
  const newestByID = new Map<string, number>();
  for (const marker of markers) {
    const timestamp = marker.lastReportedAt.getTime();
    if (timestamp < cutoff || timestamp > now.getTime()) continue;
    const existing = newestByID.get(marker.id);
    if (existing === undefined || timestamp > existing) {
      newestByID.set(marker.id, timestamp);
    }
  }
  return [...newestByID.values()].sort((left, right) => right - left);
}

export function messageAuthorPatternEvaluation(input: {
  reportedMessages: MessageAuthorPatternMarker[];
  reporters: MessageAuthorPatternMarker[];
  now: Date;
}): {
  distinctMessageCount: number;
  distinctReporterCount: number;
  messagePatternReviewUntil: Date | null;
  isActive: boolean;
} {
  const messageTimes = recentDistinctMarkerTimes(input.reportedMessages, input.now);
  const reporterTimes = recentDistinctMarkerTimes(input.reporters, input.now);
  if (messageTimes.length < 3 || reporterTimes.length < 2) {
    return {
      distinctMessageCount: messageTimes.length,
      distinctReporterCount: reporterTimes.length,
      messagePatternReviewUntil: null,
      isActive: false,
    };
  }
  const qualifiedAt = Math.min(messageTimes[2], reporterTimes[1]);
  const reviewUntil = new Date(qualifiedAt + MESSAGE_AUTHOR_PATTERN_WINDOW_MILLIS);
  return {
    distinctMessageCount: messageTimes.length,
    distinctReporterCount: reporterTimes.length,
    messagePatternReviewUntil: reviewUntil,
    isActive: reviewUntil.getTime() > input.now.getTime(),
  };
}

export type MessageEvidenceRetention = {
  retentionClass: MessageEvidenceRetentionClass;
  deleteAfter: Date | null;
};

export function messageEvidenceRetention(input: {
  reviewState: MessageReviewState;
  decision: MessageEvidenceDecision | null;
  decisionAt: Date | null;
  appealState: MessageEvidenceAppealState;
  appealResolvedAt: Date | null;
  legalHoldActive: boolean;
}): MessageEvidenceRetention {
  if (input.legalHoldActive) {
    return {retentionClass: "legalHold", deleteAfter: null};
  }
  if (input.reviewState === "open" || input.reviewState === "inReview") {
    return {retentionClass: "reviewOpen", deleteAfter: null};
  }
  if (input.decision === null || input.decisionAt === null) {
    throw new Error("terminal review requires a decision and decisionAt");
  }
  if (input.appealState === "open") {
    return {retentionClass: "appealOpen", deleteAfter: null};
  }
  if (input.appealState === "resolved") {
    if (input.appealResolvedAt === null) {
      throw new Error("resolved appeal requires appealResolvedAt");
    }
    return {
      retentionClass: "deleteAfterDecision",
      deleteAfter: new Date(input.appealResolvedAt.getTime()),
    };
  }
  const sanctionDecision = input.decision === "temporaryRestriction" ||
    input.decision === "permanentSuspension";
  if (sanctionDecision) {
    return {
      retentionClass: "sanctionAppeal30Days",
      deleteAfter: new Date(
        input.decisionAt.getTime() + MESSAGE_SANCTION_APPEAL_RETENTION_MILLIS,
      ),
    };
  }
  return {
    retentionClass: "deleteAfterDecision",
    deleteAfter: new Date(input.decisionAt.getTime()),
  };
}

export function isMessageEvidenceCleanupDue(
  retention: MessageEvidenceRetention,
  now: Date,
): boolean {
  return retention.deleteAfter !== null &&
    retention.deleteAfter.getTime() <= now.getTime();
}

const EVIDENCE_TRANSITIONS: Record<MessageEvidenceState, Set<MessageEvidenceState>> = {
  copyPending: new Set(["copying", "failed"]),
  copying: new Set(["copyPending", "available", "failed"]),
  available: new Set(["cleanupPending"]),
  cleanupPending: new Set(["deleting"]),
  deleting: new Set(["cleanupPending", "deleted"]),
  deleted: new Set(),
  failed: new Set(),
};

export function canTransitionMessageEvidence(
  from: MessageEvidenceState,
  to: MessageEvidenceState,
): boolean {
  return EVIDENCE_TRANSITIONS[from].has(to);
}

const JOB_TRANSITIONS: Record<MessageEvidenceJobState, Set<MessageEvidenceJobState>> = {
  pending: new Set(["processing"]),
  processing: new Set(["retryPending", "succeeded", "failed"]),
  retryPending: new Set(["processing", "failed"]),
  succeeded: new Set(),
  failed: new Set(),
};

export function canTransitionMessageEvidenceJob(
  from: MessageEvidenceJobState,
  to: MessageEvidenceJobState,
): boolean {
  return JOB_TRANSITIONS[from].has(to);
}

const CLEANUP_JOB_TRANSITIONS: Record<
  MessageEvidenceCleanupJobState,
  Set<MessageEvidenceCleanupJobState>
> = {
  awaitingEvidence: new Set(["pending", "failed"]),
  pending: new Set(["processing"]),
  processing: new Set(["retryPending", "succeeded", "failed"]),
  retryPending: new Set(["processing", "failed"]),
  succeeded: new Set(),
  failed: new Set(),
};

export function canTransitionMessageEvidenceCleanupJob(
  from: MessageEvidenceCleanupJobState,
  to: MessageEvidenceCleanupJobState,
): boolean {
  return CLEANUP_JOB_TRANSITIONS[from].has(to);
}
