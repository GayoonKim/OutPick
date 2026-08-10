/* eslint-disable require-jsdoc, max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {
  GENERAL_REPORT_SLO_MILLIS,
  REPORT_BURST_LIMIT_PER_MINUTE,
  REPORT_RATE_BUCKET_TTL_MILLIS,
  REPORT_SCHEMA_VERSION,
  ReportReason,
  ReportReceipt,
  ReportReviewState,
  ReportTargetType,
  SubmitRoomReportInput,
  SubmitUserReportInput,
  assertReportBurstCapacity,
  nextAcceptedReportAggregate,
  reportMinuteBucket,
  reportPriority,
  reportRateBucketID,
  reportSlaDueAt,
  reportSubmissionID,
  utf8Snapshot,
} from "./contracts.js";

type ReportInput = {
  targetType: ReportTargetType;
  targetUID: string | null;
  roomID: string | null;
  reason: ReportReason;
  detail: string | null;
  triggerMessageID: string | null;
  clientRequestID: string;
};

function integerValue(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ?
    value : fallback;
}

function storedReviewState(value: unknown): ReportReviewState {
  return value === "open" || value === "inReview" || value === "resolved" ||
    value === "dismissed" ? value : "open";
}

function timestampISO(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function mediaKind(message: FirebaseFirestore.DocumentData | undefined): "images" | "video" | null {
  const attachments = Array.isArray(message?.attachments) ? message.attachments : [];
  if (attachments.some((item) => item && typeof item === "object" &&
    (item as {type?: unknown}).type === "video")) return "video";
  if (attachments.some((item) => item && typeof item === "object" &&
    (item as {type?: unknown}).type === "image")) return "images";
  return null;
}

function inspectionSummary(
  message: FirebaseFirestore.DocumentData | undefined,
): Record<string, unknown> | null {
  const value = message?.mediaInspectionSummary;
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : null;
}

export async function submitUserReportService(
  reporterUID: string,
  input: SubmitUserReportInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<ReportReceipt> {
  return submitReport(reporterUID, {
    targetType: "user",
    targetUID: input.targetUID,
    roomID: input.roomID,
    reason: input.reason,
    detail: input.detail,
    triggerMessageID: input.triggerMessageID,
    clientRequestID: input.clientRequestID,
  }, now, firestore);
}

export async function submitRoomReportService(
  reporterUID: string,
  input: SubmitRoomReportInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<ReportReceipt> {
  return submitReport(reporterUID, {
    targetType: "room",
    targetUID: null,
    roomID: input.roomID,
    reason: input.reason,
    detail: input.detail,
    triggerMessageID: input.triggerMessageID,
    clientRequestID: input.clientRequestID,
  }, now, firestore);
}

async function submitReport(
  reporterUID: string,
  input: ReportInput,
  now: Date,
  firestore: Firestore,
): Promise<ReportReceipt> {
  const nowTimestamp = Timestamp.fromDate(now);
  const reporterAccountRef = firestore.collection("moderationAccounts").doc(reporterUID);
  const roomRef = input.roomID ? firestore.collection("Rooms").doc(input.roomID) : null;
  const targetUserRef = input.targetUID ? firestore.collection("users").doc(input.targetUID) : null;
  const targetAccountRef = input.targetUID ?
    firestore.collection("moderationAccounts").doc(input.targetUID) : null;

  return firestore.runTransaction(async (transaction) => {
    const reporterAccount = await transaction.get(reporterAccountRef);
    const reporterPrincipalID = reporterAccount.get("moderationPrincipalID");
    if (!reporterAccount.exists || typeof reporterPrincipalID !== "string" || !reporterPrincipalID) {
      throw new HttpsError("failed-precondition", "신고자 제재 주체를 확인할 수 없습니다.");
    }

    let targetID: string;
    if (input.targetType === "user") {
      if (!targetUserRef || !targetAccountRef || !input.targetUID) {
        throw new HttpsError("invalid-argument", "신고 대상 사용자가 필요합니다.");
      }
      const [targetUser, targetAccount] = await Promise.all([
        transaction.get(targetUserRef),
        transaction.get(targetAccountRef),
      ]);
      if (!targetUser.exists || targetUser.get("accountStatus") !== "active") {
        throw new HttpsError("not-found", "신고 대상 사용자를 찾을 수 없습니다.");
      }
      const targetPrincipalID = targetAccount.get("moderationPrincipalID");
      if (!targetAccount.exists || typeof targetPrincipalID !== "string" || !targetPrincipalID) {
        throw new HttpsError("failed-precondition", "신고 대상의 제재 주체를 확인할 수 없습니다.");
      }
      if (targetPrincipalID === reporterPrincipalID) {
        throw new HttpsError("failed-precondition", "본인은 신고할 수 없습니다.");
      }
      targetID = targetPrincipalID;
    } else {
      if (!input.roomID) {
        throw new HttpsError("invalid-argument", "신고 대상 방이 필요합니다.");
      }
      targetID = input.roomID;
    }

    const aggregateRef = firestore
      .collection(input.targetType === "user" ? "moderationUserReports" : "moderationRoomReports")
      .doc(targetID);
    const submissionID = reportSubmissionID({
      reporterModerationPrincipalID: reporterPrincipalID,
      targetType: input.targetType,
      targetID,
      clientRequestID: input.clientRequestID,
    });
    const submissionRef = aggregateRef.collection("submissions").doc(submissionID);
    const existingSubmission = await transaction.get(submissionRef);
    if (existingSubmission.exists) {
      const receivedAt = timestampISO(existingSubmission.get("createdAt"));
      if (!receivedAt) {
        throw new HttpsError("failed-precondition", "기존 신고 접수 시각이 올바르지 않습니다.");
      }
      return {submissionID, deduplicated: true, receivedAt};
    }

    let messageData: FirebaseFirestore.DocumentData | undefined;
    if (roomRef) {
      const room = await transaction.get(roomRef);
      if (!room.exists) {
        throw new HttpsError("not-found", "신고 대상 방을 찾을 수 없습니다.");
      }
      const reporterMember = await transaction.get(roomRef.collection("members").doc(reporterUID));
      if (!reporterMember.exists) {
        throw new HttpsError("permission-denied", "이 방을 신고할 권한이 없습니다.");
      }
      if (input.targetUID) {
        const targetMember = await transaction.get(roomRef.collection("members").doc(input.targetUID));
        if (!targetMember.exists) {
          throw new HttpsError("failed-precondition", "신고 대상이 이 방의 참여자가 아닙니다.");
        }
      }
      if (input.triggerMessageID) {
        const message = await transaction.get(
          roomRef.collection("Messages").doc(input.triggerMessageID),
        );
        if (!message.exists || message.get("isDeleted") === true) {
          throw new HttpsError("not-found", "신고 문맥 메시지를 찾을 수 없습니다.");
        }
        if (input.targetUID && message.get("senderUID") !== input.targetUID) {
          throw new HttpsError("failed-precondition", "메시지 작성자와 신고 대상이 일치하지 않습니다.");
        }
        messageData = message.data();
      }
    }

    const reporterRef = aggregateRef.collection("reporters").doc(reporterPrincipalID);
    const rateRef = firestore.collection("moderationReportRateLimitBuckets")
      .doc(reportRateBucketID(reporterPrincipalID, now));
    const [aggregate, reporter, rateBucket] = await Promise.all([
      transaction.get(aggregateRef),
      transaction.get(reporterRef),
      transaction.get(rateRef),
    ]);
    const acceptedCount = integerValue(rateBucket.get("acceptedCount"), 0);
    if (acceptedCount >= REPORT_BURST_LIMIT_PER_MINUTE) {
      console.warn("[moderation-report] rate limited", {
        minuteBucket: reportMinuteBucket(now),
      });
      assertReportBurstCapacity(acceptedCount, now);
    }

    const aggregateData = aggregate.data();
    const previousReasonCounts = aggregateData?.reasonCounts;
    const reasonCounts = previousReasonCounts && typeof previousReasonCounts === "object" &&
      !Array.isArray(previousReasonCounts) ? previousReasonCounts as Partial<
        Record<ReportReason, number>
      > : {};
    const nextAggregate = nextAcceptedReportAggregate({
      exists: aggregate.exists,
      reporterExists: reporter.exists,
      reviewState: storedReviewState(aggregateData?.reviewState),
      reviewRevision: integerValue(aggregateData?.reviewRevision, 0),
      caseVersion: integerValue(aggregateData?.caseVersion, 0),
      uniqueReporterCount: integerValue(aggregateData?.uniqueReporterCount, 0),
      totalSubmissionCount: integerValue(aggregateData?.totalSubmissionCount, 0),
      reasonCounts,
      reason: input.reason,
    });
    const priorityClass = aggregate.exists && aggregateData?.priorityClass === "urgent" ?
      "urgent" : reportPriority(input.reason);
    const requestedSlaDueAt = Timestamp.fromDate(reportSlaDueAt(input.reason, now));
    const previousSlaDueAt = aggregateData?.slaDueAt;
    const slaDueAt = previousSlaDueAt instanceof Timestamp &&
      previousSlaDueAt.toMillis() < requestedSlaDueAt.toMillis() ?
      previousSlaDueAt : requestedSlaDueAt;

    transaction.set(rateRef, {
      schemaVersion: REPORT_SCHEMA_VERSION,
      reporterModerationPrincipalID: reporterPrincipalID,
      minuteBucket: reportMinuteBucket(now),
      acceptedCount: acceptedCount + 1,
      updatedAt: nowTimestamp,
      expiresAt: Timestamp.fromMillis(now.getTime() + REPORT_RATE_BUCKET_TTL_MILLIS),
    });
    transaction.set(submissionRef, {
      schemaVersion: REPORT_SCHEMA_VERSION,
      reporterModerationPrincipalID: reporterPrincipalID,
      reason: input.reason,
      detail: input.detail,
      roomID: input.roomID,
      triggerMessageID: input.triggerMessageID,
      textSnapshot: utf8Snapshot(messageData?.message),
      mediaKind: mediaKind(messageData),
      mediaInspectionSummary: inspectionSummary(messageData),
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    transaction.set(reporterRef, {
      schemaVersion: REPORT_SCHEMA_VERSION,
      firstReportedAt: reporter.exists ? reporter.get("firstReportedAt") : nowTimestamp,
      lastReportedAt: nowTimestamp,
      submissionCount: integerValue(reporter.get("submissionCount"), 0) + 1,
      expiresAt: null,
    });
    transaction.set(aggregateRef, {
      schemaVersion: REPORT_SCHEMA_VERSION,
      reviewState: nextAggregate.reviewState,
      reviewRevision: nextAggregate.reviewRevision,
      caseVersion: nextAggregate.caseVersion,
      uniqueReporterCount: nextAggregate.uniqueReporterCount,
      totalSubmissionCount: nextAggregate.totalSubmissionCount,
      reasonCounts: nextAggregate.reasonCounts,
      priorityClass,
      slaDueAt,
      firstReportedAt: aggregate.exists ? aggregate.get("firstReportedAt") : nowTimestamp,
      lastReportedAt: nowTimestamp,
      updatedAt: nowTimestamp,
      expiresAt: null,
    });

    return {
      submissionID,
      deduplicated: false,
      receivedAt: now.toISOString(),
    };
  });
}

export const reportSloMaximumMillis = GENERAL_REPORT_SLO_MILLIS;
