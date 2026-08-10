/* eslint-disable require-jsdoc, max-len */
import {
  FieldPath,
  Firestore,
  Query,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {
  assertAuditReplay,
  moderationAuditActionID,
} from "../audit/contracts.js";
import {ReportReviewState, ReportTargetType} from "../reports/contracts.js";
import {
  GetModerationReportDetailInput,
  ListModerationReportsInput,
  MutateAccountModerationInput,
  MutateModerationReviewInput,
  reviewStateForAction,
} from "./contracts.js";

const ADMIN_READ_LIMIT_PER_MINUTE = 120;
const ADMIN_MUTATION_LIMIT_PER_MINUTE = 30;
const ADMIN_RATE_BUCKET_TTL_MILLIS = 2 * 24 * 60 * 60 * 1000;

type CursorPayload = {
  kind: "reports" | "submissions";
  scope: string;
  values: Array<string | number>;
};

function encodeCursor(payload: CursorPayload): string {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function decodeCursor(value: string, kind: CursorPayload["kind"], scope: string): CursorPayload {
  try {
    const parsed = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as CursorPayload;
    if (parsed.kind !== kind || parsed.scope !== scope || !Array.isArray(parsed.values)) {
      throw new Error("scope mismatch");
    }
    return parsed;
  } catch {
    throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
  }
}

function timestampMillis(value: unknown): number {
  if (!(value instanceof Timestamp)) {
    throw new HttpsError("failed-precondition", "신고 시각 데이터가 올바르지 않습니다.");
  }
  return value.toMillis();
}

function timestampISO(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function reportCollectionName(targetType: ReportTargetType): string {
  return targetType === "user" ? "moderationUserReports" : "moderationRoomReports";
}

function safeAggregate(
  targetType: ReportTargetType,
  id: string,
  data: FirebaseFirestore.DocumentData,
): Record<string, unknown> {
  return {
    targetType,
    targetID: id,
    reviewState: data.reviewState,
    reviewRevision: data.reviewRevision,
    caseVersion: data.caseVersion,
    uniqueReporterCount: data.uniqueReporterCount,
    totalSubmissionCount: data.totalSubmissionCount,
    reasonCounts: data.reasonCounts ?? {},
    priorityClass: data.priorityClass,
    slaDueAt: timestampISO(data.slaDueAt),
    firstReportedAt: timestampISO(data.firstReportedAt),
    lastReportedAt: timestampISO(data.lastReportedAt),
    updatedAt: timestampISO(data.updatedAt),
  };
}

function safeSubmission(
  id: string,
  data: FirebaseFirestore.DocumentData,
): Record<string, unknown> {
  return {
    submissionID: id,
    reason: data.reason,
    detail: typeof data.detail === "string" ? data.detail : null,
    roomID: typeof data.roomID === "string" ? data.roomID : null,
    triggerMessageID: typeof data.triggerMessageID === "string" ? data.triggerMessageID : null,
    textSnapshot: typeof data.textSnapshot === "string" ? data.textSnapshot : null,
    mediaKind: typeof data.mediaKind === "string" ? data.mediaKind : null,
    mediaInspectionSummary: data.mediaInspectionSummary ?? null,
    createdAt: timestampISO(data.createdAt),
  };
}

export async function assertActivePlatformAdmin(
  uid: string,
  firestore: Firestore = db,
): Promise<void> {
  const snapshot = await firestore.collection("platformAdmins").doc(uid).get();
  if (!snapshot.exists || snapshot.get("isActive") !== true ||
    snapshot.get("revokedAt") instanceof Timestamp) {
    throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
  }
}

export async function consumeAdminRateLimit(
  actorUID: string,
  kind: "read" | "mutation",
  now = new Date(),
  firestore: Firestore = db,
): Promise<void> {
  const minuteBucket = Math.floor(now.getTime() / 60_000);
  const limit = kind === "read" ? ADMIN_READ_LIMIT_PER_MINUTE :
    ADMIN_MUTATION_LIMIT_PER_MINUTE;
  const reference = firestore.collection("moderationAdminRateLimitBuckets")
    .doc(`${actorUID}_${kind}_${minuteBucket}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const storedCount = snapshot.get("requestCount");
    const requestCount = typeof storedCount === "number" &&
      Number.isSafeInteger(storedCount) && storedCount >= 0 ? storedCount : 0;
    if (requestCount >= limit) {
      throw new HttpsError(
        "resource-exhausted",
        "관리자 요청이 많습니다. 잠시 후 다시 시도해 주세요.",
        {
          errorCode: "RATE_LIMITED",
          retryAt: new Date((minuteBucket + 1) * 60_000).toISOString(),
        },
      );
    }
    transaction.set(reference, {
      schemaVersion: 1,
      actorUID,
      kind,
      minuteBucket,
      requestCount: requestCount + 1,
      updatedAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromMillis(now.getTime() + ADMIN_RATE_BUCKET_TTL_MILLIS),
    });
  });
}

export async function listModerationReportsService(
  input: ListModerationReportsInput,
  firestore: Firestore = db,
): Promise<{items: Record<string, unknown>[]; nextCursor: string | null}> {
  const scope = [input.targetType, input.reviewState ?? "*", input.priorityClass ?? "*"].join(":");
  let query: Query = firestore.collection(reportCollectionName(input.targetType));
  if (input.reviewState) query = query.where("reviewState", "==", input.reviewState);
  if (input.priorityClass) query = query.where("priorityClass", "==", input.priorityClass);
  query = query
    .orderBy("reviewState", "asc")
    .orderBy("priorityClass", "desc")
    .orderBy("slaDueAt", "asc")
    .orderBy("lastReportedAt", "desc")
    .orderBy(FieldPath.documentId(), "asc");
  if (input.cursor) {
    const cursor = decodeCursor(input.cursor, "reports", scope);
    if (cursor.values.length !== 5) {
      throw new HttpsError("invalid-argument", "cursor 값이 올바르지 않습니다.");
    }
    query = query.startAfter(
      cursor.values[0],
      cursor.values[1],
      Timestamp.fromMillis(Number(cursor.values[2])),
      Timestamp.fromMillis(Number(cursor.values[3])),
      cursor.values[4],
    );
  }
  const snapshot = await query.limit(input.pageSize + 1).get();
  const visible = snapshot.docs.slice(0, input.pageSize);
  const last = visible.at(-1);
  return {
    items: visible.map((document) => safeAggregate(input.targetType, document.id, document.data())),
    nextCursor: snapshot.size > input.pageSize && last ? encodeCursor({
      kind: "reports",
      scope,
      values: [
        String(last.get("reviewState")),
        String(last.get("priorityClass")),
        timestampMillis(last.get("slaDueAt")),
        timestampMillis(last.get("lastReportedAt")),
        last.id,
      ],
    }) : null,
  };
}

export async function getModerationReportDetailService(
  input: GetModerationReportDetailInput,
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const aggregateRef = firestore.collection(reportCollectionName(input.targetType)).doc(input.targetID);
  const aggregate = await aggregateRef.get();
  if (!aggregate.exists || !aggregate.data()) {
    throw new HttpsError("not-found", "신고 건을 찾을 수 없습니다.");
  }
  const scope = `${input.targetType}:${input.targetID}`;
  let query: Query = aggregateRef.collection("submissions")
    .orderBy("createdAt", "desc")
    .orderBy(FieldPath.documentId(), "desc");
  if (input.submissionCursor) {
    const cursor = decodeCursor(input.submissionCursor, "submissions", scope);
    if (cursor.values.length !== 2) {
      throw new HttpsError("invalid-argument", "submissionCursor 값이 올바르지 않습니다.");
    }
    query = query.startAfter(
      Timestamp.fromMillis(Number(cursor.values[0])),
      cursor.values[1],
    );
  }
  const [submissions, accounts] = await Promise.all([
    query.limit(input.submissionPageSize + 1).get(),
    input.targetType === "user" ? firestore.collection("moderationAccounts")
      .where("moderationPrincipalID", "==", input.targetID)
      .limit(20)
      .get() : Promise.resolve(null),
  ]);
  const visible = submissions.docs.slice(0, input.submissionPageSize);
  const last = visible.at(-1);
  const aggregateData = aggregate.data();
  if (!aggregateData) {
    throw new HttpsError("failed-precondition", "신고 집계가 올바르지 않습니다.");
  }
  return {
    aggregate: safeAggregate(input.targetType, aggregate.id, aggregateData),
    currentUserIDs: accounts ? accounts.docs.map((document) => document.id) : [],
    submissions: visible.map((document) => safeSubmission(document.id, document.data())),
    nextSubmissionCursor: submissions.size > input.submissionPageSize && last ? encodeCursor({
      kind: "submissions",
      scope,
      values: [timestampMillis(last.get("createdAt")), last.id],
    }) : null,
  };
}

function reviewState(data: FirebaseFirestore.DocumentData | undefined): ReportReviewState {
  const value = data?.reviewState;
  if (value !== "open" && value !== "inReview" && value !== "resolved" && value !== "dismissed") {
    throw new HttpsError("failed-precondition", "신고 검토 상태가 올바르지 않습니다.");
  }
  return value;
}

export async function mutateModerationReviewService(
  actorUID: string,
  input: MutateModerationReviewInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const aggregateRef = firestore.collection(reportCollectionName(input.targetType)).doc(input.targetID);
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  return firestore.runTransaction(async (transaction) => {
    const [audit, aggregate] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(aggregateRef),
    ]);
    if (audit.exists) {
      const auditData = audit.data();
      if (!auditData) {
        throw new HttpsError("failed-precondition", "감사 로그가 올바르지 않습니다.");
      }
      return assertAuditReplay(auditData, {
        action: input.action,
        targetType: input.targetType,
        targetID: input.targetID,
        requestID: input.clientRequestID,
      });
    }
    if (!aggregate.exists || !aggregate.data()) {
      throw new HttpsError("not-found", "신고 건을 찾을 수 없습니다.");
    }
    const currentVersion = aggregate.get("caseVersion");
    if (currentVersion !== input.expectedCaseVersion) {
      throw new HttpsError("aborted", "신고 상태가 변경됐습니다. 다시 불러와 주세요.", {
        errorCode: "STALE_CASE_VERSION",
      });
    }
    const currentState = reviewState(aggregate.data());
    const nextState = reviewStateForAction(currentState, input.action);
    const result = {
      reviewState: nextState,
      reviewRevision: aggregate.get("reviewRevision"),
      caseVersion: input.expectedCaseVersion + 1,
    };
    const nowTimestamp = Timestamp.fromDate(now);
    transaction.update(aggregateRef, {
      reviewState: nextState,
      caseVersion: result.caseVersion,
      updatedAt: nowTimestamp,
    });
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      action: input.action,
      targetType: input.targetType,
      targetID: input.targetID,
      before: {
        reviewState: currentState,
        reviewRevision: aggregate.get("reviewRevision"),
        caseVersion: input.expectedCaseVersion,
      },
      after: result,
      reasonCode: input.reasonCode,
      reportTargetType: input.targetType,
      reportTargetID: input.targetID,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}

export async function mutateAccountModerationService(
  actorUID: string,
  input: MutateAccountModerationInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const targetAccountRef = firestore.collection("moderationAccounts").doc(input.targetUID);
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  return firestore.runTransaction(async (transaction) => {
    const [audit, targetAccount] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(targetAccountRef),
    ]);
    if (audit.exists) {
      const auditData = audit.data();
      if (!auditData) {
        throw new HttpsError("failed-precondition", "감사 로그가 올바르지 않습니다.");
      }
      return assertAuditReplay(auditData, {
        action: input.action,
        targetType: "user",
        targetID: input.targetUID,
        requestID: input.clientRequestID,
      });
    }
    const principalID = targetAccount.get("moderationPrincipalID");
    if (!targetAccount.exists || typeof principalID !== "string" || !principalID) {
      throw new HttpsError("not-found", "제재 대상 계정을 찾을 수 없습니다.");
    }
    const principalRef = firestore.collection("moderationPrincipals").doc(principalID);
    const linkedAccountsQuery = firestore.collection("moderationAccounts")
      .where("moderationPrincipalID", "==", principalID);
    const [principal, linkedAccounts] = await Promise.all([
      transaction.get(principalRef),
      transaction.get(linkedAccountsQuery),
    ]);
    if (!principal.exists || !principal.data()) {
      throw new HttpsError("failed-precondition", "제재 주체 문서를 찾을 수 없습니다.");
    }
    if (linkedAccounts.docs.some((document) => document.id === actorUID)) {
      throw new HttpsError("failed-precondition", "관리자는 자신을 제재할 수 없습니다.", {
        errorCode: "SELF_ADMIN_ACTION",
      });
    }
    const adminSnapshots = await Promise.all(linkedAccounts.docs.map((document) =>
      transaction.get(firestore.collection("platformAdmins").doc(document.id)),
    ));
    if (adminSnapshots.some((snapshot) => snapshot.exists &&
      snapshot.get("isActive") === true && !(snapshot.get("revokedAt") instanceof Timestamp))) {
      throw new HttpsError("failed-precondition", "활성 플랫폼 관리자는 일반 API로 제재할 수 없습니다.", {
        errorCode: "PROTECTED_ADMIN_TARGET",
      });
    }
    const currentVersion = principal.get("stateVersion");
    if (currentVersion !== input.expectedStateVersion) {
      throw new HttpsError("aborted", "계정 제재 상태가 변경됐습니다. 다시 불러와 주세요.", {
        errorCode: "STALE_STATE_VERSION",
      });
    }
    if (input.action === "temporarilyRestrictAccount" &&
      (!input.restrictedUntil || input.restrictedUntil.getTime() <= now.getTime())) {
      throw new HttpsError("invalid-argument", "제한 만료 시각은 미래여야 합니다.");
    }
    const moderationStatus = input.action === "temporarilyRestrictAccount" ? "restricted" :
      input.action === "permanentlySuspendAccount" ? "suspended" : "active";
    let restrictedUntil: Timestamp | null = null;
    if (input.action === "temporarilyRestrictAccount" && input.restrictedUntil) {
      restrictedUntil = Timestamp.fromDate(input.restrictedUntil);
    }
    const result = {
      moderationStatus,
      restrictedUntil: input.restrictedUntil?.toISOString() ?? null,
      stateVersion: input.expectedStateVersion + 1,
    };
    const before = {
      moderationStatus: principal.get("moderationStatus"),
      restrictedUntil: timestampISO(principal.get("restrictedUntil")),
      stateVersion: currentVersion,
    };
    const nowTimestamp = Timestamp.fromDate(now);
    transaction.update(principalRef, {
      moderationStatus,
      restrictedUntil,
      stateVersion: result.stateVersion,
      noticeReasonCode: input.reasonCode,
      updatedAt: nowTimestamp,
    });
    for (const account of linkedAccounts.docs) {
      transaction.update(account.ref, {
        moderationStatus,
        restrictedUntil,
        stateVersion: result.stateVersion,
        noticeReasonCode: input.reasonCode,
        updatedAt: nowTimestamp,
      });
    }
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      action: input.action,
      targetType: "user",
      targetID: input.targetUID,
      before,
      after: result,
      reasonCode: input.reasonCode,
      reportTargetType: input.reportTargetType,
      reportTargetID: input.reportTargetID,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}
