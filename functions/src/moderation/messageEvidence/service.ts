/* eslint-disable require-jsdoc, max-len */
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {requireAccountCapabilityData} from "../../shared/accountStatus.js";
import {
  REPORT_RATE_BUCKET_TTL_MILLIS,
  REPORT_SCHEMA_VERSION,
  MessageReportReceipt,
  SubmitMessageReportInput,
  assertReportBurstCapacity,
  reportMinuteBucket,
  reportPriority,
  reportRateBucketID,
  reportSlaDueAt,
  utf8Snapshot,
} from "../reports/contracts.js";
import {
  MESSAGE_EVIDENCE_CONTRACT_VERSION,
  MESSAGE_REPORT_REQUEST_RECEIPT_TTL_MILLIS,
  MESSAGE_REPORT_PREPARATION_TTL_MILLIS,
  MessageQueueClass,
  MessageReportStatus,
  messageEvidenceBundleID,
  messageEvidenceCopyJobID,
  messageAuthorPatternEvaluation,
  messageReportQueueEvaluation,
  messageGuardID,
  messageIncidentID,
  messageReportPreparationID,
  messageReportRequestID,
  messageReportSubmissionID,
  messageReporterID,
  messageReviewRevisionID,
  nextMessageQueueClass,
  nextMessageReviewRevision,
} from "./contracts.js";

export type MessageEvidenceSourceObject = {
  attachmentID: string;
  bucket: string;
  path: string;
  generation: string;
  bytes: number;
  contentType: string;
};

function integer(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

function timestampISO(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function visibility(value: unknown): "visible" | "deleted" {
  return value === "deleted" ? "deleted" : "visible";
}

function queue(value: unknown): MessageQueueClass | null {
  return value === "holding" || value === "reviewRequired" || value === "urgent" ? value : null;
}

function receiptFromData(data: FirebaseFirestore.DocumentData): MessageReportReceipt {
  const status = data.status as MessageReportStatus;
  if (!["processing", "accepted", "alreadyReported", "failed", "messageAlreadyDeleted"].includes(status)) {
    throw new HttpsError("failed-precondition", "기존 메시지 신고 요청 상태가 올바르지 않습니다.");
  }
  return {
    status,
    submissionID: typeof data.submissionID === "string" ? data.submissionID : null,
    deduplicated: true,
    alreadyReported: status === "alreadyReported",
    queueClass: queue(data.queueClass),
    visibilityState: visibility(data.visibilityState),
    receivedAt: timestampISO(data.receivedAt),
    originalReceivedAt: timestampISO(data.originalReceivedAt ?? data.receivedAt),
    seq: Number.isSafeInteger(data.seq) ? data.seq : null,
  };
}

function boundedMap(value: unknown, maximumBytes: number): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const json = JSON.stringify(value);
  if (Buffer.byteLength(json, "utf8") > maximumBytes) {
    throw new HttpsError("failed-precondition", "메시지 증거 문맥이 허용 범위를 초과했습니다.");
  }
  return JSON.parse(json) as Record<string, unknown>;
}

function sourceObjects(message: FirebaseFirestore.DocumentData): MessageEvidenceSourceObject[] {
  const attachments = Array.isArray(message.attachments) ? message.attachments : [];
  if (attachments.length < 1 || attachments.length > 30) {
    throw new HttpsError("failed-precondition", "신고할 미디어 증거 구성이 올바르지 않습니다.");
  }
  const output = attachments.map((raw) => {
    const item = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    const result = {
      attachmentID: typeof item.attachmentID === "string" ? item.attachmentID : "",
      bucket: typeof item.bucketOriginal === "string" ? item.bucketOriginal : "",
      path: typeof item.pathOriginal === "string" ? item.pathOriginal : "",
      generation: typeof item.generationOriginal === "string" ? item.generationOriginal : "",
      bytes: integer(item.bytesOriginal, -1),
      contentType: typeof item.contentTypeOriginal === "string" ? item.contentTypeOriginal : "",
    };
    if (!result.attachmentID || !result.bucket || !result.path || !result.generation || result.bytes <= 0 || !result.contentType) {
      throw new HttpsError("failed-precondition", "ready 미디어 증거 descriptor가 없습니다.");
    }
    return result;
  });
  if (new Set(output.map((item) => item.attachmentID)).size !== output.length) {
    throw new HttpsError("failed-precondition", "미디어 attachment ID가 중복됐습니다.");
  }
  return output;
}

function supportedMessageKind(message: FirebaseFirestore.DocumentData): "text" | "media" | "lookbookShare" {
  const type = typeof message.messageType === "string" ? message.messageType.toLowerCase() : "";
  if (type === "text") return "text";
  if (type === "image" || type === "video") return "media";
  if (type === "lookbookshare") return "lookbookShare";
  throw new HttpsError("failed-precondition", "현재 형식의 메시지는 신고할 수 없습니다.");
}

function requestDocument(input: {
  incidentID: string;
  reporterID: string;
  clientRequestID: string;
  reviewRevision: number;
  preparationID: string | null;
  submissionID: string | null;
  status: MessageReportStatus;
  queueClass: MessageQueueClass | null;
  visibilityState: "visible" | "deleted";
  seq: number | null;
  attemptGeneration: number;
  requestedAt: Timestamp;
  acceptedAt?: Timestamp | null;
}): Record<string, unknown> {
  return {
    schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION,
    incidentID: input.incidentID,
    reporterID: input.reporterID,
    clientRequestID: input.clientRequestID,
    reviewRevision: input.reviewRevision,
    preparationID: input.preparationID,
    submissionID: input.submissionID,
    attemptGeneration: input.attemptGeneration,
    status: input.status,
    queueClass: input.queueClass,
    visibilityState: input.visibilityState,
    seq: input.seq,
    receivedAt: input.status === "accepted" ? input.requestedAt : null,
    originalReceivedAt: input.status === "alreadyReported" ? input.requestedAt : null,
    acceptedAt: input.acceptedAt ?? null,
    lastErrorCode: null,
    createdAt: input.requestedAt,
    updatedAt: input.requestedAt,
    expiresAt: Timestamp.fromMillis(input.requestedAt.toMillis() + MESSAGE_REPORT_REQUEST_RECEIPT_TTL_MILLIS),
  };
}

export async function submitMessageReportService(
  reporterUID: string,
  input: SubmitMessageReportInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<MessageReportReceipt> {
  const nowTimestamp = Timestamp.fromDate(now);
  const incidentID = messageIncidentID(input.roomID, input.messageID);
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const messageRef = roomRef.collection("Messages").doc(input.messageID);
  const reporterAccountRef = firestore.collection("moderationAccounts").doc(reporterUID);

  return firestore.runTransaction(async (transaction) => {
    const [reporterAccount, room, message] = await Promise.all([
      transaction.get(reporterAccountRef),
      transaction.get(roomRef),
      transaction.get(messageRef),
    ]);
    const reporterData = requireAccountCapabilityData(
      reporterAccount.exists ? reporterAccount.data() : undefined,
      "report",
      now,
    );
    const reporterPrincipalID = reporterData.moderationPrincipalID;
    if (typeof reporterPrincipalID !== "string" || !reporterPrincipalID) {
      throw new HttpsError("failed-precondition", "신고자 제재 주체를 확인할 수 없습니다.");
    }
    const reporterID = messageReporterID(reporterPrincipalID);
    const requestID = messageReportRequestID({
      incidentID,
      reporterModerationPrincipalID: reporterPrincipalID,
      clientRequestID: input.clientRequestID,
    });
    const requestRef = firestore.collection("moderationMessageReportRequests").doc(requestID);
    const existingRequest = await transaction.get(requestRef);
    if (existingRequest.exists && existingRequest.data()) {
      const existingRequestData = existingRequest.data()!;
      if (existingRequestData.status === "processing" &&
          typeof existingRequestData.preparationID === "string") {
        const existingPreparation = await transaction.get(
          firestore.collection("moderationMessageReportPreparations")
            .doc(existingRequestData.preparationID),
        );
        if (existingPreparation.exists) {
          const requestGeneration = integer(existingRequestData.attemptGeneration);
          const preparationGeneration = integer(existingPreparation.get("attemptGeneration"));
          const wasSupersededByFailedGeneration = requestGeneration < preparationGeneration;
          const preparationStatus = existingPreparation.get("status");
          if (wasSupersededByFailedGeneration || preparationStatus === "failed") {
            const synchronized = {
              ...existingRequestData,
              status: "failed",
              lastErrorCode: wasSupersededByFailedGeneration ?
                "EVIDENCE_COPY_FAILED" : existingPreparation.get("lastErrorCode") ?? "EVIDENCE_COPY_FAILED",
              updatedAt: nowTimestamp,
            };
            transaction.set(requestRef, synchronized);
            return receiptFromData(synchronized);
          }
          if (requestGeneration === preparationGeneration && preparationStatus === "accepted") {
            const requestedAt = existingPreparation.get("requestedAt") instanceof Timestamp ?
              existingPreparation.get("requestedAt") : existingRequestData.createdAt;
            const synchronized = {
              ...existingRequestData,
              status: "accepted",
              queueClass: queue(existingPreparation.get("queueClass")),
              visibilityState: visibility(existingPreparation.get("visibilityState")),
              receivedAt: requestedAt,
              originalReceivedAt: requestedAt,
              acceptedAt: existingPreparation.get("acceptedAt") ?? nowTimestamp,
              updatedAt: nowTimestamp,
            };
            transaction.set(requestRef, synchronized);
            return receiptFromData(synchronized);
          }
        }
      }
      return receiptFromData(existingRequestData);
    }

    if (!room.exists || room.get("isClosed") === true || (room.get("lifecycleStatus") && room.get("lifecycleStatus") !== "active")) {
      throw new HttpsError("not-found", "신고 대상 채팅방을 찾을 수 없습니다.");
    }
    if (!message.exists || !message.data()) {
      throw new HttpsError("not-found", "신고 대상 메시지를 찾을 수 없습니다.");
    }
    const messageData = message.data()!;
    const seq = Number.isSafeInteger(messageData.seq) && messageData.seq > 0 ? messageData.seq : null;
    if (seq === null) {
      throw new HttpsError("failed-precondition", "신고 대상 메시지 순서가 올바르지 않습니다.");
    }
    const memberRef = roomRef.collection("members").doc(reporterUID);
    const banRef = roomRef.collection("bans").doc(reporterPrincipalID);
    const rateRef = firestore.collection("moderationReportRateLimitBuckets").doc(reportRateBucketID(reporterPrincipalID, now));
    const [member, ban, rate] = await Promise.all([
      transaction.get(memberRef), transaction.get(banRef), transaction.get(rateRef),
    ]);
    if (!member.exists && !(ban.exists && ban.get("isActive") === true)) {
      throw new HttpsError("permission-denied", "이 메시지를 신고할 읽기 권한이 없습니다.");
    }
    const acceptedCount = integer(rate.get("acceptedCount"));
    const messageRequestCount = integer(rate.get("messageRequestCount"));
    const messagePreparationCount = integer(rate.get("messagePreparationCount"));
    const consumeTransportRequest = (preparationDelta: 0 | 1): void => {
      assertReportBurstCapacity(acceptedCount + messageRequestCount, now);
      transaction.set(rateRef, {
        schemaVersion: REPORT_SCHEMA_VERSION,
        reporterModerationPrincipalID: reporterPrincipalID,
        minuteBucket: reportMinuteBucket(now),
        acceptedCount,
        messageRequestCount: messageRequestCount + 1,
        messagePreparationCount: messagePreparationCount + preparationDelta,
        technicalOperationCount: acceptedCount + messageRequestCount + 1,
        updatedAt: nowTimestamp,
        expiresAt: Timestamp.fromMillis(now.getTime() + REPORT_RATE_BUCKET_TTL_MILLIS),
      });
    };
    if (messageData.isDeleted === true || visibility(messageData.moderationVisibilityState) === "deleted") {
      const document = requestDocument({
        incidentID, reporterID, clientRequestID: input.clientRequestID,
        reviewRevision: 0, preparationID: null, submissionID: null,
        status: "messageAlreadyDeleted", queueClass: null,
        visibilityState: "deleted", seq, attemptGeneration: 0,
        requestedAt: nowTimestamp,
      });
      consumeTransportRequest(0);
      transaction.create(requestRef, document);
      return {...receiptFromData(document), deduplicated: false};
    }
    const senderUID = messageData.senderUID;
    if (typeof senderUID !== "string" || !senderUID) {
      throw new HttpsError("failed-precondition", "메시지 작성자를 확인할 수 없습니다.");
    }
    const senderAccountRef = firestore.collection("moderationAccounts").doc(senderUID);
    const incidentRef = firestore.collection("moderationMessageIncidents").doc(incidentID);
    const guardRef = firestore.collection("moderationMessageGuards").doc(messageGuardID(incidentID));
    const [senderAccount, incident, guard] = await Promise.all([
      transaction.get(senderAccountRef), transaction.get(incidentRef), transaction.get(guardRef),
    ]);
    const senderPrincipalID = senderAccount.get("moderationPrincipalID");
    if (!senderAccount.exists || typeof senderPrincipalID !== "string" || !senderPrincipalID) {
      throw new HttpsError("failed-precondition", "메시지 작성자의 제재 주체를 확인할 수 없습니다.");
    }
    if (senderPrincipalID === reporterPrincipalID) {
      throw new HttpsError("failed-precondition", "본인의 메시지는 신고할 수 없습니다.");
    }
    if (guard.exists && guard.get("contentState") === "deleted") {
      const document = requestDocument({incidentID, reporterID, clientRequestID: input.clientRequestID, reviewRevision: integer(guard.get("reviewRevision")), preparationID: null, submissionID: null, status: "messageAlreadyDeleted", queueClass: null, visibilityState: "deleted", seq, attemptGeneration: 0, requestedAt: nowTimestamp});
      consumeTransportRequest(0);
      transaction.create(requestRef, document);
      return {...receiptFromData(document), deduplicated: false};
    }

    const reviewState = incident.get("reviewState");
    const reviewRevision = nextMessageReviewRevision({
      exists: incident.exists,
      reviewState: reviewState === "inReview" || reviewState === "resolved" || reviewState === "dismissed" ? reviewState : "open",
      reviewRevision: integer(incident.get("reviewRevision")),
    });
    const continuesCurrentRevision = incident.exists &&
      integer(incident.get("reviewRevision")) === reviewRevision;
    const revisionID = messageReviewRevisionID(reviewRevision);
    const reporterRef = incidentRef.collection("revisions").doc(revisionID).collection("reporters").doc(reporterID);
    const preparationID = messageReportPreparationID({incidentID, reviewRevision, reporterModerationPrincipalID: reporterPrincipalID});
    const preparationRef = firestore.collection("moderationMessageReportPreparations").doc(preparationID);
    const bundleID = messageEvidenceBundleID(incidentID, reviewRevision);
    const bundleRef = firestore.collection("moderationMessageEvidence").doc(bundleID);
    const copyJobRef = firestore.collection("moderationEvidenceCopyJobs")
      .doc(messageEvidenceCopyJobID(bundleID));
    const [existingReporter, preparation, bundle, copyJob] = await Promise.all([
      transaction.get(reporterRef), transaction.get(preparationRef),
      transaction.get(bundleRef), transaction.get(copyJobRef),
    ]);
    const submissionID = messageReportSubmissionID({incidentID, reviewRevision, reporterModerationPrincipalID: reporterPrincipalID, clientRequestID: input.clientRequestID});
    if (existingReporter.exists) {
      const originalReceivedAt = existingReporter.get("createdAt") instanceof Timestamp ? existingReporter.get("createdAt") : nowTimestamp;
      const document = {...requestDocument({incidentID, reporterID, clientRequestID: input.clientRequestID, reviewRevision, preparationID, submissionID, status: "alreadyReported", queueClass: continuesCurrentRevision ? queue(incident.get("queueClass")) : null, visibilityState: visibility(messageData.moderationVisibilityState), seq, attemptGeneration: integer(preparation.get("attemptGeneration")), requestedAt: originalReceivedAt}), originalReceivedAt};
      consumeTransportRequest(0);
      transaction.create(requestRef, document);
      return {...receiptFromData(document), deduplicated: false};
    }
    if (preparation.exists && preparation.get("status") !== "failed") {
      const document = requestDocument({incidentID, reporterID, clientRequestID: input.clientRequestID, reviewRevision, preparationID, submissionID, status: preparation.get("status") === "accepted" ? "accepted" : "processing", queueClass: continuesCurrentRevision ? queue(incident.get("queueClass")) : null, visibilityState: visibility(messageData.moderationVisibilityState), seq, attemptGeneration: integer(preparation.get("attemptGeneration")), requestedAt: preparation.get("requestedAt") instanceof Timestamp ? preparation.get("requestedAt") : nowTimestamp, acceptedAt: preparation.get("acceptedAt") instanceof Timestamp ? preparation.get("acceptedAt") : null});
      consumeTransportRequest(0);
      transaction.create(requestRef, document);
      return {...receiptFromData(document), deduplicated: false};
    }

    const kind = supportedMessageKind(messageData);
    const objects = kind === "media" ? sourceObjects(messageData) : [];
    const bundleState = bundle.get("state");
    const bundleGeneration = integer(bundle.get("attemptGeneration"));
    const restartingFailedBundle = kind === "media" && bundle.exists && bundleState === "failed";
    if (kind === "media" && preparation.exists && preparation.get("status") === "failed" && !bundle.exists) {
      throw new HttpsError("failed-precondition", "실패한 evidence bundle을 확인할 수 없습니다.");
    }
    if (restartingFailedBundle) {
      const partialObjects = Array.isArray(bundle.get("objectPaths")) ? bundle.get("objectPaths") : [];
      if ((copyJob.exists && (copyJob.get("status") !== "failed" ||
          integer(copyJob.get("attemptGeneration")) !== bundleGeneration)) ||
          (preparation.exists && preparation.get("status") === "failed" &&
            integer(preparation.get("attemptGeneration")) !== bundleGeneration) ||
          partialObjects.length > 0) {
        throw new HttpsError("failed-precondition", "evidence 실패 정리가 아직 완료되지 않았습니다.");
      }
    } else if (kind === "media" && bundle.exists &&
        !["copyPending", "copying", "available"].includes(bundleState)) {
      throw new HttpsError("failed-precondition", "재사용 가능한 evidence bundle 상태가 아닙니다.");
    }
    const attemptGeneration = kind !== "media" ? 0 : restartingFailedBundle ?
      bundleGeneration + 1 : bundle.exists ? bundleGeneration : 0;
    const immediatelyAccepted = kind !== "media" || bundle.get("state") === "available";
    const priorityClass = reportPriority(input.reason);
    const status: MessageReportStatus = immediatelyAccepted ? "accepted" : "processing";
    const currentQueue = continuesCurrentRevision ? queue(incident.get("queueClass")) : null;
    const previousDistinctCount = continuesCurrentRevision ? integer(incident.get("totalDistinctReporterCount24h")) : 0;
    const nextCount = previousDistinctCount + (immediatelyAccepted ? 1 : 0);
    const nextQueue = immediatelyAccepted ? nextMessageQueueClass({currentQueueClass: currentQueue, reason: input.reason, distinctAcceptedReporterCount: nextCount}) : currentQueue;
    const requestDoc = requestDocument({incidentID, reporterID, clientRequestID: input.clientRequestID, reviewRevision, preparationID, submissionID, status, queueClass: nextQueue, visibilityState: visibility(messageData.moderationVisibilityState), seq, attemptGeneration, requestedAt: nowTimestamp, acceptedAt: immediatelyAccepted ? nowTimestamp : null});

    const acceptedVisibility = visibility(messageData.moderationVisibilityState);
    let acceptedUrgentCount = (continuesCurrentRevision ? integer(incident.get("urgentDistinctReporterCount24h")) : 0) + (priorityClass === "urgent" ? 1 : 0);
    let acceptedTotalCount = nextCount;
    let authorAggregate: FirebaseFirestore.DocumentSnapshot | null = null;
    let authorReporter: FirebaseFirestore.DocumentSnapshot | null = null;
    let reportedMessageMarker: FirebaseFirestore.DocumentSnapshot | null = null;
    let messageReporterMarker: FirebaseFirestore.DocumentSnapshot | null = null;
    let authorPattern: ReturnType<typeof messageAuthorPatternEvaluation> | null = null;
    if (immediatelyAccepted) {
      const reporterCollection = incidentRef.collection("revisions").doc(revisionID).collection("reporters");
      const cutoff = Timestamp.fromMillis(now.getTime() - 24 * 60 * 60 * 1000);
      const [recentReporters, recentUrgent] = await Promise.all([
        transaction.get(reporterCollection.where("createdAt", ">=", cutoff).orderBy("createdAt", "desc").limit(3)),
        transaction.get(reporterCollection.where("priorityClass", "==", "urgent").where("createdAt", ">=", cutoff).orderBy("createdAt", "desc").limit(2)),
      ]);
      const signals = [...recentReporters.docs, ...recentUrgent.docs].map((document) => ({
        reporterModerationPrincipalID: document.id,
        priority: document.get("priorityClass") === "urgent" ? "urgent" as const : "general" as const,
        receivedAt: document.get("createdAt") instanceof Timestamp ? document.get("createdAt").toDate() : now,
      }));
      signals.push({reporterModerationPrincipalID: reporterID, priority: priorityClass, receivedAt: now});
      const globalEvaluation = messageReportQueueEvaluation(signals, now);
      acceptedUrgentCount = globalEvaluation.urgentDistinctReporterCount;
      acceptedTotalCount = globalEvaluation.totalDistinctReporterCount;

      const authorAggregateRef = firestore.collection("moderationUserReports").doc(senderPrincipalID);
      const authorReporterRef = authorAggregateRef.collection("reporters").doc(reporterPrincipalID);
      const reportedMessageRef = authorAggregateRef.collection("reportedMessages").doc(incidentID);
      const messageReporterRef = authorAggregateRef.collection("messageReporters").doc(reporterID);
      const [aggregateSnapshot, reporterSnapshot, messageMarkerSnapshot, reporterMarkerSnapshot, recentMessages, recentMessageReporters] = await Promise.all([
        transaction.get(authorAggregateRef), transaction.get(authorReporterRef),
        transaction.get(reportedMessageRef), transaction.get(messageReporterRef),
        transaction.get(authorAggregateRef.collection("reportedMessages").orderBy("lastReportedAt", "desc").limit(3)),
        transaction.get(authorAggregateRef.collection("messageReporters").orderBy("lastReportedAt", "desc").limit(2)),
      ]);
      authorAggregate = aggregateSnapshot;
      authorReporter = reporterSnapshot;
      reportedMessageMarker = messageMarkerSnapshot;
      messageReporterMarker = reporterMarkerSnapshot;
      authorPattern = messageAuthorPatternEvaluation({
        reportedMessages: [...recentMessages.docs.map((document) => ({id: document.id, lastReportedAt: document.get("lastReportedAt") instanceof Timestamp ? document.get("lastReportedAt").toDate() : now})), {id: incidentID, lastReportedAt: now}],
        reporters: [...recentMessageReporters.docs.map((document) => ({id: document.id, lastReportedAt: document.get("lastReportedAt") instanceof Timestamp ? document.get("lastReportedAt").toDate() : now})), {id: reporterID, lastReportedAt: now}],
        now,
      });
    }

    requestDoc.visibilityState = acceptedVisibility;

    consumeTransportRequest(1);
    transaction.create(requestRef, requestDoc);
    const preparationCreatedAt = preparation.exists ? preparation.get("createdAt") ?? nowTimestamp : nowTimestamp;
    const preparationDocument: Record<string, unknown> = {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, incidentID, roomID: input.roomID, messageID: input.messageID, seq, reviewRevision, reporterID, reporterModerationPrincipalID: reporterPrincipalID, senderModerationPrincipalID: senderPrincipalID, bundleID, initialRequestID: requestID, reason: input.reason, detail: input.detail, priorityClass, attemptGeneration, status, queueClass: immediatelyAccepted ? nextQueue : null, visibilityState: immediatelyAccepted ? acceptedVisibility : null, lastErrorCode: null, requestedAt: nowTimestamp, acceptedAt: immediatelyAccepted ? nowTimestamp : null, failedAt: null, createdAt: preparationCreatedAt, updatedAt: nowTimestamp};
    if (immediatelyAccepted) {
      for (const key of ["roomID", "messageID", "seq", "reporterID", "reporterModerationPrincipalID", "senderModerationPrincipalID", "bundleID", "reason", "detail", "priorityClass"]) delete preparationDocument[key];
      preparationDocument.expiresAt = Timestamp.fromMillis((preparationCreatedAt as Timestamp).toMillis() + MESSAGE_REPORT_PREPARATION_TTL_MILLIS);
    }
    transaction.set(preparationRef, preparationDocument);
    if (!bundle.exists) {
      transaction.create(bundleRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID: input.roomID, messageID: input.messageID, reviewRevision, textSnapshot: utf8Snapshot(messageData.message ?? messageData.msg), replyContextSnapshot: boundedMap(messageData.replyPreview, 4_000), sharedContentSnapshot: kind === "lookbookShare" ? boundedMap(messageData.sharedContent, 16_000) : null, attachmentIDs: objects.map((item) => item.attachmentID), sourceObjects: objects, evidenceObjects: [], attemptGeneration, acceptanceState: immediatelyAccepted ? "reviewable" : "notReady", pendingPreparationCount: immediatelyAccepted ? 0 : 1, totalDisplayBytes: objects.reduce((sum, item) => sum + item.bytes, 0), objectPaths: [], state: immediatelyAccepted ? "available" : "copyPending", retentionClass: "reviewOpen", createdAt: nowTimestamp, deleteAfter: null, updatedAt: nowTimestamp});
    } else if (restartingFailedBundle) {
      transaction.set(bundleRef, {textSnapshot: utf8Snapshot(messageData.message ?? messageData.msg), replyContextSnapshot: boundedMap(messageData.replyPreview, 4_000), sharedContentSnapshot: null, attachmentIDs: objects.map((item) => item.attachmentID), sourceObjects: objects, evidenceObjects: [], attemptGeneration, acceptanceState: "notReady", pendingPreparationCount: 1, totalDisplayBytes: objects.reduce((sum, item) => sum + item.bytes, 0), objectPaths: [], state: "copyPending", retentionClass: "reviewOpen", deleteAfter: null, updatedAt: nowTimestamp}, {merge: true});
    } else if (!immediatelyAccepted) {
      transaction.set(bundleRef, {pendingPreparationCount: integer(bundle.get("pendingPreparationCount")) + 1, updatedAt: nowTimestamp}, {merge: true});
    }
    if (!guard.exists) {
      transaction.create(guardRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID: input.roomID, messageID: input.messageID, contentState: "active", guardWinner: "reportFirst", evidenceState: immediatelyAccepted ? "available" : "copyPending", bundleID, reviewRevision, updatedAt: nowTimestamp});
    } else if (immediatelyAccepted || restartingFailedBundle) {
      transaction.set(guardRef, {guardWinner: "reportFirst", evidenceState: immediatelyAccepted ? "available" : "copyPending", bundleID, reviewRevision, updatedAt: nowTimestamp}, {merge: true});
    }
    if (!immediatelyAccepted && (!bundle.exists || restartingFailedBundle)) {
      transaction.set(copyJobRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID: input.roomID, messageID: input.messageID, bundleID, incidentID, reviewRevision, messageType: String(messageData.messageType).toLowerCase(), attemptGeneration, sourceObjects: objects, evidenceObjects: [], status: "pending", phase: "copying", attempt: 0, finalizationAttempt: 0, nextAttemptAt: nowTimestamp, leaseToken: null, leaseExpiresAt: null, lastErrorCode: null, createdAt: copyJob.exists ? copyJob.get("createdAt") ?? nowTimestamp : nowTimestamp, updatedAt: nowTimestamp});
    } else {
      const revisionRef = incidentRef.collection("revisions").doc(revisionID);
      transaction.set(reporterRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, reason: input.reason, detail: input.detail, clientRequestID: input.clientRequestID, priorityClass, evidenceBundleID: bundleID, createdAt: nowTimestamp});
      transaction.set(revisionRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, reviewState: "open", queueClass: nextQueue, openedAt: incident.exists && incident.get("reviewRevision") === reviewRevision ? incident.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, acceptanceState: "reviewable", resolvedAt: null, resolutionActionID: null, evidenceBundleID: bundleID, updatedAt: nowTimestamp});
      const previousReasonCounts = continuesCurrentRevision && incident.get("reasonCounts") && typeof incident.get("reasonCounts") === "object" && !Array.isArray(incident.get("reasonCounts")) ? incident.get("reasonCounts") as Record<string, number> : {};
      const revisionReasonCounts = {...previousReasonCounts, [input.reason]: integer(previousReasonCounts[input.reason]) + 1};
      transaction.set(incidentRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID: input.roomID, messageID: input.messageID, senderModerationPrincipalID: senderPrincipalID, reviewRevision, reviewState: "open", acceptanceState: "reviewable", pendingPreparationCount: 0, caseVersion: integer(incident.get("caseVersion")) + 1, queueClass: nextQueue, priorityClass, reasonCounts: revisionReasonCounts, urgentDistinctReporterCount24h: acceptedUrgentCount, totalDistinctReporterCount24h: acceptedTotalCount, reviewDueAt: Timestamp.fromDate(reportSlaDueAt("other", now)), slaDueAt: Timestamp.fromDate(reportSlaDueAt(input.reason, now)), visibilityState: acceptedVisibility, evidenceState: "available", firstReportedAt: continuesCurrentRevision ? incident.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp});
      if (authorAggregate && authorReporter && reportedMessageMarker && messageReporterMarker && authorPattern) {
        const authorAggregateRef = firestore.collection("moderationUserReports").doc(senderPrincipalID);
        const previousReasons = authorAggregate.get("reasonCounts");
        const reasonCounts = previousReasons && typeof previousReasons === "object" && !Array.isArray(previousReasons) ? previousReasons as Record<string, number> : {};
        transaction.set(authorAggregateRef, {schemaVersion: REPORT_SCHEMA_VERSION, reviewState: authorAggregate.exists ? authorAggregate.get("reviewState") ?? "open" : "open", reviewRevision: integer(authorAggregate.get("reviewRevision")), caseVersion: integer(authorAggregate.get("caseVersion")) + 1, uniqueReporterCount: integer(authorAggregate.get("uniqueReporterCount")) + (authorReporter.exists ? 0 : 1), totalSubmissionCount: integer(authorAggregate.get("totalSubmissionCount")) + 1, reasonCounts: {...reasonCounts, [input.reason]: integer(reasonCounts[input.reason]) + 1}, priorityClass: authorAggregate.get("priorityClass") === "urgent" || priorityClass === "urgent" ? "urgent" : "general", slaDueAt: authorAggregate.get("slaDueAt") instanceof Timestamp && authorAggregate.get("slaDueAt").toMillis() < reportSlaDueAt(input.reason, now).getTime() ? authorAggregate.get("slaDueAt") : Timestamp.fromDate(reportSlaDueAt(input.reason, now)), firstReportedAt: authorAggregate.exists ? authorAggregate.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp, expiresAt: null, messagePatternQualifiedAt: authorPattern.isActive ? nowTimestamp : authorAggregate.get("messagePatternQualifiedAt") ?? null, messagePatternReviewUntil: authorPattern.messagePatternReviewUntil ? Timestamp.fromDate(authorPattern.messagePatternReviewUntil) : authorAggregate.get("messagePatternReviewUntil") ?? null}, {merge: true});
        transaction.set(authorAggregateRef.collection("reporters").doc(reporterPrincipalID), {schemaVersion: REPORT_SCHEMA_VERSION, firstReportedAt: authorReporter.exists ? authorReporter.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, lastReportedAt: nowTimestamp, submissionCount: integer(authorReporter.get("submissionCount")) + 1, expiresAt: null}, {merge: true});
        transaction.set(authorAggregateRef.collection("reportedMessages").doc(incidentID), {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID: input.roomID, messageID: input.messageID, latestReviewRevision: reviewRevision, firstReportedAt: reportedMessageMarker.exists ? reportedMessageMarker.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
        transaction.set(authorAggregateRef.collection("messageReporters").doc(reporterID), {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, firstReportedAt: messageReporterMarker.exists ? messageReporterMarker.get("firstReportedAt") ?? nowTimestamp : nowTimestamp, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
      }
    }
    return {...receiptFromData(requestDoc), deduplicated: false};
  });
}

export type AcceptMessageEvidenceBundleResult = {
  acceptedPreparationCount: number;
  remainingPreparationCount: number;
  acceptanceState: "draining" | "reviewable";
};

export async function acceptMessageEvidenceBundleService(
  bundleID: string,
  attemptGeneration: number,
  now = new Date(),
  firestore: Firestore = db,
): Promise<AcceptMessageEvidenceBundleResult> {
  if (!Number.isSafeInteger(attemptGeneration) || attemptGeneration < 0) {
    throw new HttpsError("invalid-argument", "evidence attempt generation이 올바르지 않습니다.");
  }
  const bundleRef = firestore.collection("moderationMessageEvidence").doc(bundleID);
  const nowTimestamp = Timestamp.fromDate(now);
  return firestore.runTransaction(async (transaction) => {
    const bundle = await transaction.get(bundleRef);
    if (!bundle.exists || bundle.get("state") !== "available" || integer(bundle.get("attemptGeneration")) !== attemptGeneration) {
      throw new HttpsError("failed-precondition", "접수 가능한 메시지 evidence 상태가 아닙니다.");
    }
    const roomID = bundle.get("roomID");
    const messageID = bundle.get("messageID");
    const reviewRevision = integer(bundle.get("reviewRevision"));
    if (typeof roomID !== "string" || typeof messageID !== "string") {
      throw new HttpsError("failed-precondition", "메시지 evidence 식별자가 올바르지 않습니다.");
    }
    const preparationsQuery = firestore.collection("moderationMessageReportPreparations")
      .where("bundleID", "==", bundleID).where("status", "==", "processing")
      .orderBy("requestedAt", "asc").limit(31);
    const preparationsSnapshot = await transaction.get(preparationsQuery);
    const preparationDocuments = preparationsSnapshot.docs.slice(0, 30);
    const remainingPreparationCount = Math.max(0, preparationsSnapshot.size - preparationDocuments.length);
    const acceptanceState = remainingPreparationCount > 0 ? "draining" as const : "reviewable" as const;
    const incidentID = messageIncidentID(roomID, messageID);
    const incidentRef = firestore.collection("moderationMessageIncidents").doc(incidentID);
    const revisionRef = incidentRef.collection("revisions").doc(messageReviewRevisionID(reviewRevision));
    const messageRef = firestore.collection("Rooms").doc(roomID).collection("Messages").doc(messageID);
    const guardRef = firestore.collection("moderationMessageGuards").doc(incidentID);
    const [incident, message, guard] = await Promise.all([
      transaction.get(incidentRef), transaction.get(messageRef), transaction.get(guardRef),
    ]);
    const continuesCurrentRevision = incident.exists &&
      integer(incident.get("reviewRevision")) === reviewRevision;
    if (guard.get("guardWinner") !== "reportFirst" || guard.get("bundleID") !== bundleID) {
      throw new HttpsError("aborted", "메시지 삭제와 evidence 접수 순서가 변경됐습니다.");
    }
    if (preparationDocuments.length === 0) {
      transaction.set(bundleRef, {acceptanceState: "reviewable", pendingPreparationCount: 0, updatedAt: nowTimestamp}, {merge: true});
      if (incident.exists) {
        transaction.set(incidentRef, {acceptanceState: "reviewable", pendingPreparationCount: 0, updatedAt: nowTimestamp}, {merge: true});
        transaction.set(revisionRef, {acceptanceState: "reviewable", updatedAt: nowTimestamp}, {merge: true});
      }
      transaction.set(guardRef, {evidenceState: "available", updatedAt: nowTimestamp}, {merge: true});
      return {acceptedPreparationCount: 0, remainingPreparationCount: 0, acceptanceState: "reviewable"};
    }

    const initialRequestRefs = preparationDocuments.map((document) => {
      const initialRequestID = document.get("initialRequestID");
      if (typeof initialRequestID !== "string" || !initialRequestID) {
        throw new HttpsError("failed-precondition", "최초 메시지 신고 receipt를 확인할 수 없습니다.");
      }
      return firestore.collection("moderationMessageReportRequests").doc(initialRequestID);
    });
    const initialRequests = await transaction.getAll(...initialRequestRefs);
    if (initialRequests.some((request, index) =>
      !request.exists || request.get("preparationID") !== preparationDocuments[index].id ||
      integer(request.get("attemptGeneration")) !== integer(preparationDocuments[index].get("attemptGeneration")))) {
      throw new HttpsError("failed-precondition", "최초 메시지 신고 receipt 연결이 올바르지 않습니다.");
    }
    const reporterRefs = preparationDocuments.map((document) =>
      revisionRef.collection("reporters").doc(String(document.get("reporterID"))),
    );
    const existingReporters = await transaction.getAll(...reporterRefs);
    const acceptedPreparations = preparationDocuments.filter((_, index) => !existingReporters[index].exists);
    const cutoff = Timestamp.fromMillis(now.getTime() - 24 * 60 * 60 * 1000);
    const reporterCollection = revisionRef.collection("reporters");
    const [recentReporters, recentUrgent] = await Promise.all([
      transaction.get(reporterCollection.where("createdAt", ">=", cutoff).orderBy("createdAt", "desc").limit(3)),
      transaction.get(reporterCollection.where("priorityClass", "==", "urgent").where("createdAt", ">=", cutoff).orderBy("createdAt", "desc").limit(2)),
    ]);
    const signals = [...recentReporters.docs, ...recentUrgent.docs].map((document) => ({
      reporterModerationPrincipalID: document.id,
      priority: document.get("priorityClass") === "urgent" ? "urgent" as const : "general" as const,
      receivedAt: document.get("createdAt") instanceof Timestamp ? document.get("createdAt").toDate() : now,
    }));
    for (const preparation of acceptedPreparations) {
      signals.push({
        reporterModerationPrincipalID: String(preparation.get("reporterID")),
        priority: preparation.get("priorityClass") === "urgent" ? "urgent" : "general",
        receivedAt: preparation.get("requestedAt") instanceof Timestamp ? preparation.get("requestedAt").toDate() : now,
      });
    }
    const globalEvaluation = messageReportQueueEvaluation(signals, now);
    let queueClass = continuesCurrentRevision ? queue(incident.get("queueClass")) : null;
    for (const preparation of acceptedPreparations) {
      queueClass = nextMessageQueueClass({
        currentQueueClass: queueClass,
        reason: preparation.get("reason"),
        distinctAcceptedReporterCount: globalEvaluation.totalDistinctReporterCount,
      });
    }
    const visibilityState = message.exists && message.get("isDeleted") === true ? "deleted" as const :
      visibility(message.get("moderationVisibilityState"));
    const senderPrincipalID = preparationDocuments[0].get("senderModerationPrincipalID");
    if (typeof senderPrincipalID !== "string" || !senderPrincipalID) {
      throw new HttpsError("failed-precondition", "evidence 작성자 제재 주체가 올바르지 않습니다.");
    }
    const authorAggregateRef = firestore.collection("moderationUserReports").doc(senderPrincipalID);
    const authorReporterRefs = acceptedPreparations.map((document) =>
      authorAggregateRef.collection("reporters").doc(String(document.get("reporterModerationPrincipalID"))),
    );
    const reportedMessageRef = authorAggregateRef.collection("reportedMessages").doc(incidentID);
    const messageReporterRefs = acceptedPreparations.map((document) =>
      authorAggregateRef.collection("messageReporters").doc(String(document.get("reporterID"))),
    );
    const [authorAggregate, reportedMessageMarker, recentMessages, recentMessageReporters] = await Promise.all([
      transaction.get(authorAggregateRef), transaction.get(reportedMessageRef),
      transaction.get(authorAggregateRef.collection("reportedMessages").orderBy("lastReportedAt", "desc").limit(3)),
      transaction.get(authorAggregateRef.collection("messageReporters").orderBy("lastReportedAt", "desc").limit(2)),
    ]);
    const authorReporters = authorReporterRefs.length > 0 ? await transaction.getAll(...authorReporterRefs) : [];
    const messageReporterMarkers = messageReporterRefs.length > 0 ? await transaction.getAll(...messageReporterRefs) : [];
    const authorPattern = messageAuthorPatternEvaluation({
      reportedMessages: [...recentMessages.docs.map((document) => ({id: document.id, lastReportedAt: document.get("lastReportedAt") instanceof Timestamp ? document.get("lastReportedAt").toDate() : now})), {id: incidentID, lastReportedAt: now}],
      reporters: [...recentMessageReporters.docs.map((document) => ({id: document.id, lastReportedAt: document.get("lastReportedAt") instanceof Timestamp ? document.get("lastReportedAt").toDate() : now})), ...acceptedPreparations.map((document) => ({id: String(document.get("reporterID")), lastReportedAt: now}))],
      now,
    });
    const firstRequestedAt = preparationDocuments.reduce<Timestamp>((earliest, document) => {
      const requestedAt = document.get("requestedAt");
      return requestedAt instanceof Timestamp && requestedAt.toMillis() < earliest.toMillis() ? requestedAt : earliest;
    }, nowTimestamp);

    for (let index = 0; index < preparationDocuments.length; index += 1) {
      const preparation = preparationDocuments[index];
      const requestedAt = preparation.get("requestedAt") instanceof Timestamp ? preparation.get("requestedAt") : nowTimestamp;
      const createdAt = preparation.get("createdAt") instanceof Timestamp ? preparation.get("createdAt") as Timestamp : nowTimestamp;
      transaction.set(preparation.ref, {status: "accepted", queueClass, visibilityState, acceptedAt: nowTimestamp, updatedAt: nowTimestamp, expiresAt: Timestamp.fromMillis(createdAt.toMillis() + MESSAGE_REPORT_PREPARATION_TTL_MILLIS), roomID: FieldValue.delete(), messageID: FieldValue.delete(), seq: FieldValue.delete(), reporterID: FieldValue.delete(), reporterModerationPrincipalID: FieldValue.delete(), senderModerationPrincipalID: FieldValue.delete(), bundleID: FieldValue.delete(), reason: FieldValue.delete(), detail: FieldValue.delete(), priorityClass: FieldValue.delete()}, {merge: true});
      if (!existingReporters[index].exists) {
        transaction.create(reporterRefs[index], {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, reason: preparation.get("reason"), detail: preparation.get("detail") ?? null, clientRequestID: initialRequests[index].get("clientRequestID") ?? null, priorityClass: preparation.get("priorityClass"), evidenceBundleID: bundleID, createdAt: requestedAt});
      }
      if (initialRequests[index].exists) {
        transaction.set(initialRequestRefs[index], {status: "accepted", receivedAt: requestedAt, originalReceivedAt: requestedAt, acceptedAt: nowTimestamp, queueClass, visibilityState, updatedAt: nowTimestamp}, {merge: true});
      }
    }

    const reasonCountsValue = continuesCurrentRevision ? incident.get("reasonCounts") : null;
    const reasonCounts = reasonCountsValue && typeof reasonCountsValue === "object" && !Array.isArray(reasonCountsValue) ? {...reasonCountsValue as Record<string, number>} : {};
    let priorityClass = continuesCurrentRevision && incident.get("priorityClass") === "urgent" ? "urgent" : "general";
    let slaDueAt = continuesCurrentRevision && incident.get("slaDueAt") instanceof Timestamp ? incident.get("slaDueAt") as Timestamp : Timestamp.fromDate(reportSlaDueAt("other", firstRequestedAt.toDate()));
    for (const preparation of acceptedPreparations) {
      const reason = String(preparation.get("reason"));
      reasonCounts[reason] = integer(reasonCounts[reason]) + 1;
      if (preparation.get("priorityClass") === "urgent") priorityClass = "urgent";
      const requestedAt = preparation.get("requestedAt") instanceof Timestamp ? preparation.get("requestedAt").toDate() : now;
      const candidate = Timestamp.fromDate(reportSlaDueAt(preparation.get("reason"), requestedAt));
      if (candidate.toMillis() < slaDueAt.toMillis()) slaDueAt = candidate;
    }
    const revisionFirstReportedAt = continuesCurrentRevision && incident.get("firstReportedAt") instanceof Timestamp ? incident.get("firstReportedAt") as Timestamp : firstRequestedAt;
    const reviewDueAt = continuesCurrentRevision && incident.get("reviewDueAt") instanceof Timestamp ? incident.get("reviewDueAt") as Timestamp : Timestamp.fromDate(reportSlaDueAt("other", firstRequestedAt.toDate()));
    transaction.set(incidentRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID, messageID, senderModerationPrincipalID: senderPrincipalID, reviewRevision, reviewState: "open", acceptanceState, pendingPreparationCount: remainingPreparationCount, caseVersion: integer(incident.get("caseVersion")) + acceptedPreparations.length, queueClass, priorityClass, reasonCounts, urgentDistinctReporterCount24h: globalEvaluation.urgentDistinctReporterCount, totalDistinctReporterCount24h: globalEvaluation.totalDistinctReporterCount, reviewDueAt, slaDueAt, visibilityState, evidenceState: "available", firstReportedAt: revisionFirstReportedAt, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
    transaction.set(revisionRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, reviewState: "open", queueClass, openedAt: revisionFirstReportedAt, acceptanceState, resolvedAt: null, resolutionActionID: null, evidenceBundleID: bundleID, updatedAt: nowTimestamp}, {merge: true});
    transaction.set(bundleRef, {acceptanceState, pendingPreparationCount: remainingPreparationCount, updatedAt: nowTimestamp}, {merge: true});
    transaction.set(guardRef, {evidenceState: "available", updatedAt: nowTimestamp}, {merge: true});
    if (acceptedPreparations.length > 0) {
      const authorReasonValue = authorAggregate.get("reasonCounts");
      const authorReasonCounts = authorReasonValue && typeof authorReasonValue === "object" && !Array.isArray(authorReasonValue) ? {...authorReasonValue as Record<string, number>} : {};
      for (const preparation of acceptedPreparations) {
        const reason = String(preparation.get("reason"));
        authorReasonCounts[reason] = integer(authorReasonCounts[reason]) + 1;
      }
      const newUniqueReporterCount = authorReporters.filter((snapshot) => !snapshot.exists).length;
      transaction.set(authorAggregateRef, {schemaVersion: REPORT_SCHEMA_VERSION, reviewState: authorAggregate.exists ? authorAggregate.get("reviewState") ?? "open" : "open", reviewRevision: integer(authorAggregate.get("reviewRevision")), caseVersion: integer(authorAggregate.get("caseVersion")) + acceptedPreparations.length, uniqueReporterCount: integer(authorAggregate.get("uniqueReporterCount")) + newUniqueReporterCount, totalSubmissionCount: integer(authorAggregate.get("totalSubmissionCount")) + acceptedPreparations.length, reasonCounts: authorReasonCounts, priorityClass: authorAggregate.get("priorityClass") === "urgent" || priorityClass === "urgent" ? "urgent" : "general", slaDueAt: authorAggregate.get("slaDueAt") instanceof Timestamp && authorAggregate.get("slaDueAt").toMillis() < slaDueAt.toMillis() ? authorAggregate.get("slaDueAt") : slaDueAt, firstReportedAt: authorAggregate.exists ? authorAggregate.get("firstReportedAt") ?? firstRequestedAt : firstRequestedAt, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp, expiresAt: null, messagePatternQualifiedAt: authorPattern.isActive ? nowTimestamp : authorAggregate.get("messagePatternQualifiedAt") ?? null, messagePatternReviewUntil: authorPattern.messagePatternReviewUntil ? Timestamp.fromDate(authorPattern.messagePatternReviewUntil) : authorAggregate.get("messagePatternReviewUntil") ?? null}, {merge: true});
      acceptedPreparations.forEach((preparation, index) => {
        const requestedAt = preparation.get("requestedAt") instanceof Timestamp ? preparation.get("requestedAt") : nowTimestamp;
        transaction.set(authorReporterRefs[index], {schemaVersion: REPORT_SCHEMA_VERSION, firstReportedAt: authorReporters[index].exists ? authorReporters[index].get("firstReportedAt") ?? requestedAt : requestedAt, lastReportedAt: requestedAt, submissionCount: integer(authorReporters[index].get("submissionCount")) + 1, expiresAt: null}, {merge: true});
        transaction.set(messageReporterRefs[index], {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, firstReportedAt: messageReporterMarkers[index].exists ? messageReporterMarkers[index].get("firstReportedAt") ?? requestedAt : requestedAt, lastReportedAt: requestedAt, updatedAt: nowTimestamp}, {merge: true});
      });
      transaction.set(reportedMessageRef, {schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, roomID, messageID, latestReviewRevision: reviewRevision, firstReportedAt: reportedMessageMarker.exists ? reportedMessageMarker.get("firstReportedAt") ?? firstRequestedAt : firstRequestedAt, lastReportedAt: nowTimestamp, updatedAt: nowTimestamp}, {merge: true});
    }
    return {acceptedPreparationCount: acceptedPreparations.length, remainingPreparationCount, acceptanceState};
  });
}
