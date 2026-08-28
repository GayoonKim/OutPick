/* eslint-disable require-jsdoc, max-len */
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {
  applySingleMessageDeletionMutation,
  messageCleanupJobID,
} from "../../chat/deletion/mutation.js";
import {roomOwnershipSuccessionJobID} from "../../chat/moderation/roomMembershipSweep.js";
import {moderationAuditActionID} from "../audit/contracts.js";
import {
  MESSAGE_EVIDENCE_CONTRACT_VERSION,
  messageEvidenceCleanupJobID,
  messageEvidenceRetention,
  messageReviewRevisionID,
} from "../messageEvidence/contracts.js";
import {ResolveMessageModerationInput} from "./contracts.js";

function replayResult(data: FirebaseFirestore.DocumentData, input: ResolveMessageModerationInput): Record<string, unknown> {
  const restrictedUntil = input.restrictedUntil?.toISOString() ?? null;
  if (data.action !== "resolveMessageModeration" || data.targetType !== "message" ||
      data.targetID !== input.incidentID || data.requestID !== input.clientRequestID ||
      data.after?.reviewOutcome !== input.reviewOutcome ||
      data.after?.contentAction !== input.contentAction ||
      data.after?.accountAction !== input.accountAction ||
      data.after?.reviewRevision !== input.reviewRevision ||
      data.after?.restrictedUntil !== restrictedUntil ||
      data.before?.caseVersion !== input.expectedCaseVersion ||
      data.before?.accountStateVersion !== input.expectedAccountStateVersion ||
      data.reasonCode !== input.reasonCode) {
    throw new HttpsError("already-exists", "같은 clientRequestID가 다른 관리자 작업에 사용됐습니다.");
  }
  return data.after as Record<string, unknown>;
}

export async function resolveMessageModerationService(
  actorUID: string,
  input: ResolveMessageModerationInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const actionID = moderationAuditActionID(actorUID, input.clientRequestID);
  const auditRef = firestore.collection("moderationAuditLogs").doc(actionID);
  const incidentRef = firestore.collection("moderationMessageIncidents").doc(input.incidentID);
  return firestore.runTransaction(async (transaction) => {
    const [audit, incident] = await Promise.all([transaction.get(auditRef), transaction.get(incidentRef)]);
    if (audit.exists && audit.data()) return replayResult(audit.data()!, input);
    if (!incident.exists || !incident.data()) throw new HttpsError("not-found", "메시지 신고 건을 찾을 수 없습니다.");
    if (incident.get("reviewRevision") !== input.reviewRevision) {
      throw new HttpsError("aborted", "메시지 신고 revision이 변경됐습니다.", {errorCode: "STALE_REVIEW_REVISION"});
    }
    if (incident.get("caseVersion") !== input.expectedCaseVersion) {
      throw new HttpsError("aborted", "메시지 신고 상태가 변경됐습니다.", {errorCode: "STALE_CASE_VERSION"});
    }
    if (incident.get("acceptanceState") !== "reviewable") {
      throw new HttpsError("failed-precondition", "Evidence 접수 drain이 끝나지 않았습니다.", {errorCode: "EVIDENCE_DRAINING"});
    }
    if (incident.get("reviewState") !== "open" && incident.get("reviewState") !== "inReview") {
      throw new HttpsError("failed-precondition", "이미 종료된 메시지 신고입니다.");
    }
    const roomID = incident.get("roomID");
    const messageID = incident.get("messageID");
    const targetPrincipalID = incident.get("senderModerationPrincipalID");
    if (typeof roomID !== "string" || typeof messageID !== "string" || typeof targetPrincipalID !== "string") {
      throw new HttpsError("failed-precondition", "메시지 신고 대상 식별자가 올바르지 않습니다.");
    }
    const revisionRef = incidentRef.collection("revisions").doc(messageReviewRevisionID(input.reviewRevision));
    const roomRef = firestore.collection("Rooms").doc(roomID);
    const messageRef = roomRef.collection("Messages").doc(messageID);
    const guardRef = firestore.collection("moderationMessageGuards").doc(input.incidentID);
    const [revision, room, message, guard] = await Promise.all([
      transaction.get(revisionRef), transaction.get(roomRef), transaction.get(messageRef),
      transaction.get(guardRef),
    ]);
    if (!revision.exists || revision.get("reviewState") !== incident.get("reviewState")) {
      throw new HttpsError("failed-precondition", "현재 review revision 상태가 올바르지 않습니다.");
    }
    if (!room.exists || !message.exists || !message.data()) {
      throw new HttpsError("failed-precondition", "신고 대상 메시지를 찾을 수 없습니다.");
    }
    const bundleID = revision.get("evidenceBundleID");
    if (typeof bundleID !== "string") throw new HttpsError("failed-precondition", "Evidence bundle 식별자가 없습니다.");
    const bundleRef = firestore.collection("moderationMessageEvidence").doc(bundleID);
    const bundle = await transaction.get(bundleRef);
    if (!bundle.exists || bundle.get("state") !== "available" || bundle.get("acceptanceState") !== "reviewable") {
      throw new HttpsError("failed-precondition", "결정 가능한 Evidence bundle 상태가 아닙니다.");
    }

    const sanctionsAccount = input.accountAction === "temporaryRestriction" || input.accountAction === "permanentSuspension";
    const confirmedViolation = input.reviewOutcome === "violation";
    const linkedAccountsQuery = firestore.collection("moderationAccounts").where("moderationPrincipalID", "==", targetPrincipalID);
    const principalRef = firestore.collection("moderationPrincipals").doc(targetPrincipalID);
    const [principal, linkedAccounts] = sanctionsAccount ? await Promise.all([
      transaction.get(principalRef), transaction.get(linkedAccountsQuery),
    ]) : [null, null];
    if (sanctionsAccount) {
      if (!principal?.exists || principal.get("stateVersion") !== input.expectedAccountStateVersion) {
        throw new HttpsError("aborted", "계정 제재 상태가 변경됐습니다.", {errorCode: "STALE_ACCOUNT_STATE_VERSION"});
      }
      if (!linkedAccounts || linkedAccounts.empty) throw new HttpsError("failed-precondition", "제재 대상 계정 연결을 찾을 수 없습니다.");
      if (linkedAccounts.docs.some((document) => document.id === actorUID)) {
        throw new HttpsError("failed-precondition", "관리자는 자신을 제재할 수 없습니다.", {errorCode: "SELF_ADMIN_ACTION"});
      }
      const adminSnapshots = await Promise.all(linkedAccounts.docs.map((document) =>
        transaction.get(firestore.collection("platformAdmins").doc(document.id))));
      if (adminSnapshots.some((snapshot) => snapshot.exists && snapshot.get("isActive") === true && !(snapshot.get("revokedAt") instanceof Timestamp))) {
        throw new HttpsError("failed-precondition", "활성 플랫폼 관리자는 일반 API로 제재할 수 없습니다.", {errorCode: "PROTECTED_ADMIN_TARGET"});
      }
      if (input.accountAction === "temporaryRestriction" && (!input.restrictedUntil || input.restrictedUntil.getTime() <= now.getTime())) {
        throw new HttpsError("invalid-argument", "제한 만료 시각은 미래여야 합니다.");
      }
    }

    const messageData = message.data()!;
    const publicCleanupRef = firestore.collection("chatMessageCleanupJobs").doc(messageCleanupJobID(roomID, messageID));
    const violationsRef = firestore.collection("moderationConfirmedViolations").doc(targetPrincipalID);
    const recentViolationsQuery = violationsRef.collection("incidents")
      .where("confirmedAt", ">=", Timestamp.fromMillis(now.getTime() - 90 * 24 * 60 * 60 * 1_000));
    const [publicCleanup, violations, recentViolations] = confirmedViolation ? await Promise.all([
      transaction.get(publicCleanupRef),
      transaction.get(violationsRef),
      transaction.get(recentViolationsQuery),
    ]) : [null, null, null];

    const nowTimestamp = Timestamp.fromDate(now);
    const nextReviewState = input.reviewOutcome === "dismissed" ? "dismissed" : "resolved";
    const nextCaseVersion = input.expectedCaseVersion + 1;
    const keepsExistingContent = input.contentAction === "keep" && messageData.isDeleted !== true;
    const retention = messageEvidenceRetention({
      reviewState: nextReviewState,
      accountAction: input.accountAction,
      decisionAt: now,
      appealState: "none",
      appealResolvedAt: null,
      legalHoldActive: false,
    });
    const result: Record<string, unknown> = {
      incidentID: input.incidentID,
      reviewRevision: input.reviewRevision,
      reviewState: nextReviewState,
      reviewOutcome: input.reviewOutcome,
      contentAction: input.contentAction,
      accountAction: input.accountAction,
      restrictedUntil: input.restrictedUntil?.toISOString() ?? null,
      caseVersion: nextCaseVersion,
      messageVisibilityState: keepsExistingContent ? "visible" : "deleted",
      accountModerationStatus: input.accountAction === "temporaryRestriction" ? "restricted" :
        input.accountAction === "permanentSuspension" ? "suspended" : null,
      retentionClass: retention.retentionClass,
      evidenceDeleteAfter: retention.deleteAfter?.toISOString() ?? null,
      accountStateVersion: sanctionsAccount ? input.expectedAccountStateVersion! + 1 : null,
    };

    transaction.update(incidentRef, {
      reviewState: nextReviewState,
      caseVersion: nextCaseVersion,
      decision: FieldValue.delete(),
      reviewOutcome: input.reviewOutcome,
      contentAction: input.contentAction,
      accountAction: input.accountAction,
      resolvedAt: nowTimestamp,
      resolutionActionID: actionID,
      visibilityState: keepsExistingContent ? "visible" : "deleted",
      updatedAt: nowTimestamp,
    });
    transaction.update(revisionRef, {
      reviewState: nextReviewState,
      decision: FieldValue.delete(),
      reviewOutcome: input.reviewOutcome,
      contentAction: input.contentAction,
      accountAction: input.accountAction,
      resolvedAt: nowTimestamp,
      resolutionActionID: actionID,
      updatedAt: nowTimestamp,
    });
    transaction.update(bundleRef, {
      retentionClass: retention.retentionClass,
      deleteAfter: retention.deleteAfter ? Timestamp.fromDate(retention.deleteAfter) : null,
      state: retention.deleteAfter && retention.deleteAfter.getTime() <= now.getTime() ? "cleanupPending" : "available",
      updatedAt: nowTimestamp,
    });

    if (input.contentAction === "keep") {
      if (keepsExistingContent) transaction.update(messageRef, {moderationVisibilityState: "visible"});
      transaction.set(guardRef, {contentState: keepsExistingContent ? "active" : "deleted", evidenceState: "available", updatedAt: nowTimestamp}, {merge: true});
    } else {
      if (!publicCleanup) {
        throw new HttpsError("failed-precondition", "삭제 cleanup 상태를 확인할 수 없습니다.");
      }
      const deletion = applySingleMessageDeletionMutation(
        transaction,
        firestore,
        roomRef,
        room,
        {
          messageRef,
          message,
          cleanupRef: publicCleanupRef,
          cleanup: publicCleanup,
          guardRef,
          guard,
        },
        roomID,
        messageID,
        nowTimestamp,
      );
      result.deletionRevision = deletion.deletionRevision;
    }

    if (confirmedViolation) {
      transaction.set(violationsRef, {
        schemaVersion: 1,
        confirmedCount90Days: (recentViolations?.size ?? 0) + 1,
        confirmedCount90DaysAsOf: nowTimestamp,
        activeWarningCount: (typeof violations?.get("activeWarningCount") === "number" ? violations.get("activeWarningCount") : 0) + (input.accountAction === "warning" ? 1 : 0),
        latestConfirmedAt: nowTimestamp,
        updatedAt: nowTimestamp,
      }, {merge: true});
      transaction.create(violationsRef.collection("incidents").doc(actionID), {
        schemaVersion: 1, incidentID: input.incidentID, reviewRevision: input.reviewRevision,
        reviewOutcome: input.reviewOutcome, contentAction: input.contentAction,
        accountAction: input.accountAction, reasonCode: input.reasonCode, confirmedAt: nowTimestamp,
        expiresAt: null,
      });
    }

    if (retention.deleteAfter && retention.deleteAfter.getTime() <= now.getTime()) {
      const cleanupRef = firestore.collection("moderationEvidenceCleanupJobs").doc(messageEvidenceCleanupJobID(bundleID));
      transaction.set(cleanupRef, {
        schemaVersion: MESSAGE_EVIDENCE_CONTRACT_VERSION, bundleID, status: "pending", phase: "deleting",
        attempt: 0, nextAttemptAt: nowTimestamp, leaseToken: null, leaseExpiresAt: null,
        createdAt: nowTimestamp, updatedAt: nowTimestamp, expiresAt: null,
      }, {merge: true});
    }

    if (sanctionsAccount && principal && linkedAccounts) {
      const nextStateVersion = input.expectedAccountStateVersion! + 1;
      const moderationStatus = input.accountAction === "temporaryRestriction" ? "restricted" : "suspended";
      const restrictedUntil = input.restrictedUntil ? Timestamp.fromDate(input.restrictedUntil) : null;
      transaction.update(principalRef, {moderationStatus, restrictedUntil, stateVersion: nextStateVersion, noticeReasonCode: input.reasonCode, updatedAt: nowTimestamp});
      for (const account of linkedAccounts.docs) {
        transaction.update(account.ref, {moderationStatus, restrictedUntil, stateVersion: nextStateVersion, noticeReasonCode: input.reasonCode, updatedAt: nowTimestamp});
        if (input.accountAction === "permanentSuspension") {
          const jobID = roomOwnershipSuccessionJobID(account.id, "permanentSuspension", nextStateVersion);
          transaction.create(firestore.collection("roomOwnershipSuccessionJobs").doc(jobID), {
            schemaVersion: 1, targetUID: account.id, cause: "permanentSuspension", expectedStateVersion: nextStateVersion,
            status: "pending", attempt: 0, nextAttemptAt: nowTimestamp, leaseOwner: null, leaseExpiresAt: null,
            lastErrorCode: null, createdAt: nowTimestamp, updatedAt: nowTimestamp, completedAt: null, expiresAt: null,
          });
        }
      }
    }

    transaction.create(auditRef, {
      schemaVersion: 1, actorUID, action: "resolveMessageModeration", targetType: "message", targetID: input.incidentID,
      before: {reviewState: incident.get("reviewState"), reviewRevision: input.reviewRevision, caseVersion: input.expectedCaseVersion, accountStateVersion: sanctionsAccount ? input.expectedAccountStateVersion : null},
      after: result, reasonCode: input.reasonCode, reportTargetType: "message", reportTargetID: input.incidentID,
      requestID: input.clientRequestID, createdAt: nowTimestamp, expiresAt: null,
    });
    return result;
  });
}
