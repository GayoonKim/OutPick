/* eslint-disable require-jsdoc, max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {requireAccountCapabilityData} from "../../shared/accountStatus.js";
import {
  assertAuditReplay,
  moderationAuditActionID,
  ModerationAuditAction,
} from "../../moderation/audit/contracts.js";
import {messageIncidentID} from "../../moderation/messageEvidence/contracts.js";
import {
  applySingleMessageDeletionMutation,
  messageCleanupJobID,
} from "../deletion/mutation.js";
import {
  AcknowledgeRoomClosureInput,
  CloseOwnedChatRoomInput,
  CloseRoomByModerationInput,
  DeleteChatMessageInput,
} from "./contracts.js";
import {
  requireRoomOwner,
  resolveRoomRoleInTransaction,
  roomRoleError,
  storedRoomMemberRole,
} from "./roomRoleService.js";

export {
  messageCleanupJobID,
  messageStorageTargets,
} from "../deletion/mutation.js";

type DeleteActorKind = "author" | "roomOwner" | "roomModerator" | "platformAdmin";
type ClosureType = "closedByOwner" | "closedByModeration";

function activePlatformAdmin(data: FirebaseFirestore.DocumentData | undefined): boolean {
  return data?.isActive === true && !(data.revokedAt instanceof Timestamp);
}

function lifecycleVersion(data: FirebaseFirestore.DocumentData): number {
  const value = data.lifecycleVersion;
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : 1;
}

function roomIsActive(data: FirebaseFirestore.DocumentData): boolean {
  return data.isClosed !== true &&
    (data.lifecycleStatus === undefined || data.lifecycleStatus === "active");
}

function messageTargetID(roomID: string, messageID: string): string {
  return `${roomID}:${messageID}`;
}

export async function deleteChatMessageService(
  actorUID: string,
  authTime: unknown,
  input: DeleteChatMessageInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  const priorAudit = await auditRef.get();
  const targetID = messageTargetID(input.roomID, input.messageID);
  if (priorAudit.exists && priorAudit.data()) {
    return assertAuditReplay(priorAudit.data()!, {
      action: "deleteMessage",
      targetType: "message",
      targetID,
      requestID: input.clientRequestID,
    });
  }
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const messageRef = roomRef.collection("Messages").doc(input.messageID);
  const adminRef = firestore.collection("platformAdmins").doc(actorUID);
  const jobRef = firestore.collection("chatMessageCleanupJobs")
    .doc(messageCleanupJobID(input.roomID, input.messageID));
  const incidentID = messageIncidentID(input.roomID, input.messageID);
  const guardRef = firestore.collection("moderationMessageGuards").doc(incidentID);
  return firestore.runTransaction(async (transaction) => {
    const [audit, currentRoom, currentMessage, currentJob, currentGuard, admin, actorAccount] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(roomRef),
      transaction.get(messageRef),
      transaction.get(jobRef),
      transaction.get(guardRef),
      transaction.get(adminRef),
      transaction.get(firestore.collection("moderationAccounts").doc(actorUID)),
    ]);
    if (audit.exists && audit.data()) {
      return assertAuditReplay(audit.data()!, {
        action: "deleteMessage",
        targetType: "message",
        targetID,
        requestID: input.clientRequestID,
      });
    }
    if (!currentRoom.exists || !currentRoom.data()) {
      throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
    }
    if (!roomIsActive(currentRoom.data()!)) {
      throw new HttpsError("failed-precondition", "폐쇄된 채팅방입니다.", {
        errorCode: "ROOM_CLOSED",
      });
    }
    if (!currentMessage.exists || !currentMessage.data()) {
      throw new HttpsError("not-found", "메시지를 찾을 수 없습니다.");
    }
    const message = currentMessage.data()!;
    if (message.messageType === "roomRoleEvent" || message.serverGenerated === true) {
      throw new HttpsError("failed-precondition", "서버 역할 이벤트는 삭제할 수 없습니다.");
    }
    if (message.seq !== input.expectedSeq) {
      throw new HttpsError("aborted", "메시지 상태가 변경됐습니다.", {
        errorCode: "STALE_MESSAGE_SEQ",
      });
    }
    let actorKind: DeleteActorKind;
    if (message.senderUID === actorUID) {
      requireAccountCapabilityData(actorAccount.exists ? actorAccount.data() : undefined, "deleteOwnUGC", now);
      actorKind = "author";
    } else if (activePlatformAdmin(admin.data())) {
      requireAccountCapabilityData(actorAccount.exists ? actorAccount.data() : undefined, "readAppContent", now);
      const authTimeMillis = typeof authTime === "number" ? authTime * 1_000 : NaN;
      if (!Number.isFinite(authTimeMillis) || now.getTime() - authTimeMillis > 5 * 60_000 ||
        authTimeMillis > now.getTime() + 30_000) {
        throw new HttpsError("unauthenticated", "관리자 작업을 위해 다시 로그인해 주세요.");
      }
      actorKind = "platformAdmin";
    } else {
      const resolved = await resolveRoomRoleInTransaction(
        transaction, firestore, input.roomID, actorUID, now,
      );
      if (resolved.role !== "owner" && resolved.role !== "moderator") {
        throw roomRoleError("NOT_ROOM_MODERATOR", "메시지 운영 삭제 권한이 없습니다.", "permission-denied");
      }
      const senderUID = message.senderUID;
      const senderMember = typeof senderUID === "string" && senderUID && !senderUID.includes("/") ?
        await transaction.get(roomRef.collection("members").doc(senderUID)) : null;
      const senderRole = senderMember?.exists ? storedRoomMemberRole(senderMember.get("role")) : null;
      if (senderMember?.exists && !senderRole) {
        throw roomRoleError("ROOM_ROLE_STATE_INVALID", "메시지 작성자의 역할 상태가 올바르지 않습니다.");
      }
      if (senderRole === "owner" && resolved.role !== "owner") {
        throw roomRoleError("TARGET_IS_OWNER", "관리자는 방장의 메시지를 삭제할 수 없습니다.");
      }
      if (senderRole === "moderator" && resolved.role !== "owner") {
        throw roomRoleError("TARGET_IS_MODERATOR", "관리자끼리는 서로 제재할 수 없습니다.");
      }
      actorKind = resolved.role === "owner" ? "roomOwner" : "roomModerator";
    }
    if (actorKind !== "author" && !input.reasonCode) {
      throw new HttpsError("invalid-argument", "관리 목적 삭제에는 reasonCode가 필요합니다.");
    }
    const nowTimestamp = Timestamp.fromDate(now);
    const mutation = applySingleMessageDeletionMutation(
      transaction,
      firestore,
      roomRef,
      currentRoom,
      {
        messageRef,
        message: currentMessage,
        cleanupRef: jobRef,
        cleanup: currentJob,
        guardRef,
        guard: currentGuard,
      },
      input.roomID,
      input.messageID,
      nowTimestamp,
    );
    const result = {
      messageID: input.messageID,
      seq: input.expectedSeq,
      isDeleted: true,
      deletionRevision: mutation.deletionRevision,
      cleanupStatus: mutation.cleanupStatus,
      deduplicated: message.isDeleted === true,
      deletedAt: mutation.deletedAt.toDate().toISOString(),
    };
    const reasonCode = input.reasonCode ?? "selfDelete";
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      actorKind,
      action: "deleteMessage",
      targetType: "message",
      targetID,
      before: {isDeleted: message.isDeleted === true, seq: message.seq},
      after: result,
      reasonCode,
      reportTargetType: input.reportTargetType,
      reportTargetID: input.reportTargetID,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}

async function closeRoomService(
  actorUID: string,
  action: ModerationAuditAction,
  closureType: ClosureType,
  input: CloseOwnedChatRoomInput | CloseRoomByModerationInput,
  reasonCode: string,
  reportTargetID: string | null,
  now: Date,
  firestore: Firestore,
): Promise<Record<string, unknown>> {
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const auditRef = firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID));
  const jobRef = firestore.collection("moderationRoomCleanupJobs").doc(input.roomID);
  return firestore.runTransaction(async (transaction) => {
    const audit = await transaction.get(auditRef);
    if (audit.exists && audit.data()) {
      return assertAuditReplay(audit.data()!, {
        action,
        targetType: "room",
        targetID: input.roomID,
        requestID: input.clientRequestID,
      });
    }
    const resolvedOwner = closureType === "closedByOwner" ?
      await resolveRoomRoleInTransaction(transaction, firestore, input.roomID, actorUID, now) : null;
    if (resolvedOwner) requireRoomOwner(resolvedOwner);
    const [room, existingJob] = await Promise.all([
      resolvedOwner ? Promise.resolve(resolvedOwner.room) : transaction.get(roomRef),
      transaction.get(jobRef),
    ]);
    if (!room.exists || !room.data()) {
      throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
    }
    const roomData = room.data()!;
    const currentVersion = lifecycleVersion(roomData);
    if (currentVersion !== input.expectedLifecycleVersion) {
      throw new HttpsError("aborted", "채팅방 상태가 변경됐습니다.", {
        errorCode: "STALE_LIFECYCLE_VERSION",
      });
    }
    if (!roomIsActive(roomData)) {
      throw new HttpsError("failed-precondition", "이미 폐쇄된 채팅방입니다.", {
        errorCode: "ROOM_CLOSED",
      });
    }
    if (existingJob.exists) {
      throw new HttpsError("failed-precondition", "채팅방 정리 작업이 이미 존재합니다.");
    }
    const nextVersion = currentVersion + 1;
    const nowTimestamp = Timestamp.fromDate(now);
    const closureNoticeCode = closureType === "closedByOwner" ?
      "ownerDeleted" : "communityGuidelineViolation";
    const result = {
      lifecycleStatus: closureType,
      lifecycleVersion: nextVersion,
      cleanupStatus: "pending",
      closedAt: now.toISOString(),
    };
    transaction.update(roomRef, {
      isClosed: true,
      lifecycleStatus: closureType,
      lifecycleVersion: nextVersion,
      closedAt: nowTimestamp,
      closureNoticeCode,
      moderationClosedAt: closureType === "closedByModeration" ? nowTimestamp : null,
      moderationClosureNoticeCode: closureType === "closedByModeration" ?
        closureNoticeCode : null,
      updatedAt: nowTimestamp,
    });
    transaction.create(jobRef, {
      schemaVersion: 2,
      roomID: input.roomID,
      lifecycleVersion: nextVersion,
      closureType,
      closureNoticeCode,
      cleanupPhase: "content",
      status: "pending",
      attempt: 0,
      nextAttemptAt: nowTimestamp,
      leaseExpiresAt: null,
      lastErrorCode: null,
      createdAt: nowTimestamp,
      updatedAt: nowTimestamp,
      expiresAt: null,
    });
    transaction.create(auditRef, {
      schemaVersion: 1,
      actorUID,
      action,
      targetType: "room",
      targetID: input.roomID,
      before: {lifecycleStatus: roomData.lifecycleStatus ?? "active", lifecycleVersion: currentVersion},
      after: result,
      reasonCode,
      reportTargetType: reportTargetID ? "room" : null,
      reportTargetID,
      requestID: input.clientRequestID,
      createdAt: nowTimestamp,
      expiresAt: null,
    });
    return result;
  });
}

export async function acknowledgeRoomClosureService(
  actorUID: string,
  input: AcknowledgeRoomClosureInput,
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const roomRef = firestore.collection("Rooms").doc(input.roomID);
  const memberRef = roomRef.collection("members").doc(actorUID);
  const userRef = firestore.collection("users").doc(actorUID);
  const joinedRef = userRef.collection("joinedRooms").doc(input.roomID);
  const roomStateRef = userRef.collection("roomStates").doc(input.roomID);
  const legacyNoticeRef = userRef.collection("roomClosureNotices").doc(input.roomID);

  return firestore.runTransaction(async (transaction) => {
    const [room, member, joined, legacyNotice] = await Promise.all([
      transaction.get(roomRef),
      transaction.get(memberRef),
      transaction.get(joinedRef),
      transaction.get(legacyNoticeRef),
    ]);
    const roomData = room.data();
    if (room.exists && roomData && roomIsActive(roomData)) {
      throw new HttpsError("failed-precondition", "종료되지 않은 채팅방입니다.", {
        errorCode: "ROOM_ACTIVE",
      });
    }
    if (member.exists) transaction.delete(memberRef);
    if (joined.exists) transaction.delete(joinedRef);
    transaction.delete(roomStateRef);
    if (legacyNotice.exists) transaction.delete(legacyNoticeRef);
    return {
      roomID: input.roomID,
      acknowledged: true,
      deduplicated: !member.exists && !joined.exists && !legacyNotice.exists,
      clientRequestID: input.clientRequestID,
    };
  });
}

export async function closeOwnedChatRoomService(
  actorUID: string,
  input: CloseOwnedChatRoomInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  const audit = await firestore.collection("moderationAuditLogs")
    .doc(moderationAuditActionID(actorUID, input.clientRequestID)).get();
  if (audit.exists && audit.data()) {
    return assertAuditReplay(audit.data()!, {
      action: "closeRoomByOwner",
      targetType: "room",
      targetID: input.roomID,
      requestID: input.clientRequestID,
    });
  }
  return closeRoomService(
    actorUID,
    "closeRoomByOwner",
    "closedByOwner",
    input,
    "ownerDeleted",
    null,
    now,
    firestore,
  );
}

export async function closeRoomByModerationService(
  actorUID: string,
  input: CloseRoomByModerationInput,
  now = new Date(),
  firestore: Firestore = db,
): Promise<Record<string, unknown>> {
  return closeRoomService(
    actorUID,
    "closeRoomByModeration",
    "closedByModeration",
    input,
    input.reasonCode,
    input.reportTargetID,
    now,
    firestore,
  );
}
