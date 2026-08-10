/* eslint-disable require-jsdoc, max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {
  optionalString,
  recordData,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {
  ReportPriorityClass,
  ReportReviewState,
  ReportTargetType,
} from "../reports/contracts.js";
import {ModerationAuditAction} from "../audit/contracts.js";

export type ListModerationReportsInput = {
  targetType: ReportTargetType;
  reviewState: ReportReviewState | null;
  priorityClass: ReportPriorityClass | null;
  pageSize: number;
  cursor: string | null;
};

export type GetModerationReportDetailInput = {
  targetType: ReportTargetType;
  targetID: string;
  submissionPageSize: number;
  submissionCursor: string | null;
};

export type MutateModerationReviewInput = {
  targetType: ReportTargetType;
  targetID: string;
  action: "startReview" | "resolveReview" | "dismissReview";
  expectedCaseVersion: number;
  reasonCode: string;
  clientRequestID: string;
};

export type MutateAccountModerationInput = {
  targetUID: string;
  action: "temporarilyRestrictAccount" | "permanentlySuspendAccount" | "liftAccountModeration";
  restrictedUntil: Date | null;
  reasonCode: string;
  reportTargetType: ReportTargetType | null;
  reportTargetID: string | null;
  expectedStateVersion: number;
  clientRequestID: string;
};

function optionalEnum<T extends string>(
  data: Record<string, unknown>,
  key: string,
  allowed: readonly T[],
): T | null {
  const value = data[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value as T;
}

function requiredEnum<T extends string>(
  data: Record<string, unknown>,
  key: string,
  allowed: readonly T[],
): T {
  const value = requiredString(data, key, 64);
  if (!allowed.includes(value as T)) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return value as T;
}

function positiveInteger(
  data: Record<string, unknown>,
  key: string,
  maximum: number,
  defaultValue?: number,
): number {
  const value = data[key];
  if ((value === undefined || value === null) && defaultValue !== undefined) {
    return defaultValue;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return Math.min(value, maximum);
}

function clientRequestID(data: Record<string, unknown>): string {
  const value = requiredString(data, "clientRequestID", 64).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpsError("invalid-argument", "clientRequestID 값이 올바르지 않습니다.");
  }
  return value;
}

function targetType(data: Record<string, unknown>): ReportTargetType {
  return requiredEnum(data, "targetType", ["user", "room"] as const);
}

export function parseListModerationReportsInput(data: unknown): ListModerationReportsInput {
  const record = recordData(data);
  return {
    targetType: targetType(record),
    reviewState: optionalEnum(
      record,
      "reviewState",
      ["open", "inReview", "resolved", "dismissed"] as const,
    ),
    priorityClass: optionalEnum(record, "priorityClass", ["urgent", "general"] as const),
    pageSize: positiveInteger(record, "pageSize", 100, 50),
    cursor: optionalString(record, "cursor", 1_024),
  };
}

export function parseGetModerationReportDetailInput(
  data: unknown,
): GetModerationReportDetailInput {
  const record = recordData(data);
  return {
    targetType: targetType(record),
    targetID: requiredDocumentID(requiredString(record, "targetID", 128), "targetID"),
    submissionPageSize: positiveInteger(record, "submissionPageSize", 100, 50),
    submissionCursor: optionalString(record, "submissionCursor", 1_024),
  };
}

export function parseMutateModerationReviewInput(data: unknown): MutateModerationReviewInput {
  const record = recordData(data);
  return {
    targetType: targetType(record),
    targetID: requiredDocumentID(requiredString(record, "targetID", 128), "targetID"),
    action: requiredEnum(
      record,
      "action",
      ["startReview", "resolveReview", "dismissReview"] as const,
    ),
    expectedCaseVersion: positiveInteger(record, "expectedCaseVersion", Number.MAX_SAFE_INTEGER),
    reasonCode: requiredString(record, "reasonCode", 64),
    clientRequestID: clientRequestID(record),
  };
}

function optionalDate(data: Record<string, unknown>, key: string): Date | null {
  const value = data[key];
  if (value === undefined || value === null) return null;
  const date = typeof value === "string" || typeof value === "number" ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", `${key} 값이 올바르지 않습니다.`);
  }
  return date;
}

export function parseMutateAccountModerationInput(data: unknown): MutateAccountModerationInput {
  const record = recordData(data);
  const action = requiredEnum(
    record,
    "action",
    ["temporarilyRestrictAccount", "permanentlySuspendAccount", "liftAccountModeration"] as const,
  );
  const restrictedUntil = optionalDate(record, "restrictedUntil");
  if (action === "temporarilyRestrictAccount" && restrictedUntil === null) {
    throw new HttpsError("invalid-argument", "일시 제한 만료 시각이 필요합니다.");
  }
  if (action !== "temporarilyRestrictAccount" && restrictedUntil !== null) {
    throw new HttpsError("invalid-argument", "이 작업에는 제한 만료 시각을 사용할 수 없습니다.");
  }
  const reportTargetType = optionalEnum(
    record,
    "reportTargetType",
    ["user", "room"] as const,
  );
  const reportTargetID = optionalString(record, "reportTargetID", 128);
  if ((reportTargetType === null) !== (reportTargetID === null)) {
    throw new HttpsError(
      "invalid-argument",
      "reportTargetType과 reportTargetID는 함께 전달해야 합니다.",
    );
  }
  return {
    targetUID: requiredDocumentID(requiredString(record, "targetUID", 128), "targetUID"),
    action,
    restrictedUntil,
    reasonCode: requiredString(record, "reasonCode", 64),
    reportTargetType,
    reportTargetID: reportTargetID ? requiredDocumentID(reportTargetID, "reportTargetID") : null,
    expectedStateVersion: positiveInteger(record, "expectedStateVersion", Number.MAX_SAFE_INTEGER),
    clientRequestID: clientRequestID(record),
  };
}

export function reviewStateForAction(
  current: ReportReviewState,
  action: MutateModerationReviewInput["action"],
): ReportReviewState {
  const next: ReportReviewState = action === "startReview" ? "inReview" :
    action === "resolveReview" ? "resolved" : "dismissed";
  const allowed = current === "open" ? ["inReview", "resolved", "dismissed"] :
    current === "inReview" ? ["resolved", "dismissed"] : [];
  if (!allowed.includes(next)) {
    throw new HttpsError("failed-precondition", "허용되지 않는 신고 검토 상태 전이입니다.");
  }
  return next;
}

export function requireRecentAdminAuth(authTimeSeconds: unknown, now: Date): void {
  if (typeof authTimeSeconds !== "number" || !Number.isFinite(authTimeSeconds) ||
    now.getTime() - authTimeSeconds * 1_000 > 5 * 60 * 1_000 ||
    authTimeSeconds * 1_000 > now.getTime() + 30_000) {
    throw new HttpsError("unauthenticated", "관리자 작업을 위해 다시 로그인해 주세요.");
  }
}

export function isAccountModerationAction(value: string): value is ModerationAuditAction {
  return value === "temporarilyRestrictAccount" ||
    value === "permanentlySuspendAccount" || value === "liftAccountModeration";
}
