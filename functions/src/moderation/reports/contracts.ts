/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  optionalDocumentID,
  optionalString,
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";

export const REPORT_SCHEMA_VERSION = 1;
export const REPORT_BURST_LIMIT_PER_MINUTE = 10;
export const REPORT_RATE_BUCKET_TTL_MILLIS = 2 * 24 * 60 * 60 * 1000;
export const URGENT_REPORT_SLO_MILLIS = 24 * 60 * 60 * 1000;
export const GENERAL_REPORT_SLO_MILLIS = 72 * 60 * 60 * 1000;

export const reportReasons = [
  "harassment",
  "hate",
  "sexual",
  "spam",
  "privacy",
  "illegalDangerous",
  "other",
] as const;

export type ReportReason = typeof reportReasons[number];
export type ReportTargetType = "user" | "room";
export type ReportPriorityClass = "urgent" | "general";
export type ReportReviewState = "open" | "inReview" | "resolved" | "dismissed";

export type SubmitUserReportInput = {
  targetUID: string;
  reason: ReportReason;
  detail: string | null;
  roomID: string | null;
  triggerMessageID: string | null;
  clientRequestID: string;
};

export type SubmitRoomReportInput = {
  roomID: string;
  reason: ReportReason;
  detail: string | null;
  triggerMessageID: string | null;
  clientRequestID: string;
};

export type ReportReceipt = {
  submissionID: string;
  deduplicated: boolean;
  receivedAt: string;
};

export function requiredReportReason(value: string): ReportReason {
  if (!reportReasons.includes(value as ReportReason)) {
    throw new HttpsError("invalid-argument", "reason 값이 올바르지 않습니다.");
  }
  return value as ReportReason;
}

function requiredClientRequestID(data: Record<string, unknown>): string {
  const value = requiredString(data, "clientRequestID", 64);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "clientRequestID 값이 올바르지 않습니다.",
    );
  }
  return value.toLowerCase();
}

export function parseSubmitUserReportInput(data: unknown): SubmitUserReportInput {
  const record = recordData(data);
  const roomID = optionalDocumentID(
    optionalString(record, "roomID", 128),
    "roomID",
  );
  const triggerMessageID = optionalDocumentID(
    optionalString(record, "triggerMessageID", 128),
    "triggerMessageID",
  );
  if (triggerMessageID !== null && roomID === null) {
    throw new HttpsError(
      "invalid-argument",
      "triggerMessageID에는 roomID가 필요합니다.",
    );
  }
  return {
    targetUID: requiredDocumentID(
      requiredString(record, "targetUID", 128),
      "targetUID",
    ),
    reason: requiredReportReason(requiredString(record, "reason", 32)),
    detail: optionalString(record, "detail", 500),
    roomID,
    triggerMessageID,
    clientRequestID: requiredClientRequestID(record),
  };
}

export function parseSubmitRoomReportInput(data: unknown): SubmitRoomReportInput {
  const record = recordData(data);
  return {
    roomID: requiredDocumentID(
      requiredString(record, "roomID", 128),
      "roomID",
    ),
    reason: requiredReportReason(requiredString(record, "reason", 32)),
    detail: optionalString(record, "detail", 500),
    triggerMessageID: optionalDocumentID(
      optionalString(record, "triggerMessageID", 128),
      "triggerMessageID",
    ),
    clientRequestID: requiredClientRequestID(record),
  };
}

export function reportPriority(reason: ReportReason): ReportPriorityClass {
  return reason === "sexual" || reason === "privacy" ||
    reason === "illegalDangerous" ? "urgent" : "general";
}

export function reportSlaDueAt(reason: ReportReason, now: Date): Date {
  const duration = reportPriority(reason) === "urgent" ?
    URGENT_REPORT_SLO_MILLIS : GENERAL_REPORT_SLO_MILLIS;
  return new Date(now.getTime() + duration);
}

export function reportSubmissionID(input: {
  reporterModerationPrincipalID: string;
  targetType: ReportTargetType;
  targetID: string;
  clientRequestID: string;
}): string {
  return createHash("sha256")
    .update([
      input.reporterModerationPrincipalID,
      input.targetType,
      input.targetID,
      input.clientRequestID,
    ].join(":"))
    .digest("hex");
}

export function reportMinuteBucket(now: Date): number {
  return Math.floor(now.getTime() / 60_000);
}

export function reportRateBucketID(
  reporterModerationPrincipalID: string,
  now: Date,
): string {
  return `${reporterModerationPrincipalID}_${reportMinuteBucket(now)}`;
}

export function reportRateLimitRetryAt(now: Date): Date {
  return new Date((reportMinuteBucket(now) + 1) * 60_000);
}

export function assertReportBurstCapacity(acceptedCount: number, now: Date): void {
  if (acceptedCount < REPORT_BURST_LIMIT_PER_MINUTE) return;
  throw new HttpsError(
    "resource-exhausted",
    "신고 요청이 많습니다. 잠시 후 다시 시도해 주세요.",
    {
      errorCode: "RATE_LIMITED",
      retryAt: reportRateLimitRetryAt(now).toISOString(),
    },
  );
}

export function nextAcceptedReportAggregate(input: {
  exists: boolean;
  reporterExists: boolean;
  reviewState: ReportReviewState;
  reviewRevision: number;
  caseVersion: number;
  uniqueReporterCount: number;
  totalSubmissionCount: number;
  reasonCounts: Partial<Record<ReportReason, number>>;
  reason: ReportReason;
}): {
  reviewState: ReportReviewState;
  reviewRevision: number;
  caseVersion: number;
  uniqueReporterCount: number;
  totalSubmissionCount: number;
  reasonCounts: Partial<Record<ReportReason, number>>;
} {
  const review = reopenReportState(input);
  return {
    ...review,
    uniqueReporterCount: input.uniqueReporterCount + (input.reporterExists ? 0 : 1),
    totalSubmissionCount: input.totalSubmissionCount + 1,
    reasonCounts: {
      ...input.reasonCounts,
      [input.reason]: (input.reasonCounts[input.reason] ?? 0) + 1,
    },
  };
}

export function reopenReportState(input: {
  exists: boolean;
  reviewState: ReportReviewState;
  reviewRevision: number;
  caseVersion: number;
}): {
  reviewState: ReportReviewState;
  reviewRevision: number;
  caseVersion: number;
} {
  if (!input.exists) {
    return {reviewState: "open", reviewRevision: 0, caseVersion: 1};
  }
  const terminal = input.reviewState === "resolved" ||
    input.reviewState === "dismissed";
  return {
    reviewState: terminal ? "open" : input.reviewState,
    reviewRevision: input.reviewRevision + (terminal ? 1 : 0),
    caseVersion: input.caseVersion + 1,
  };
}

export function utf8Snapshot(value: unknown, maximumBytes = 4_000): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  let output = "";
  let byteCount = 0;
  for (const scalar of trimmed) {
    const scalarBytes = Buffer.byteLength(scalar, "utf8");
    if (byteCount + scalarBytes > maximumBytes) break;
    output += scalar;
    byteCount += scalarBytes;
  }
  return output || null;
}
