/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../../core/firebase.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import {
  assertAuditReplay,
  moderationAuditActionID,
  ModerationAuditAction,
} from "../../moderation/audit/contracts.js";
import {messageIncidentID} from "../../moderation/messageEvidence/contracts.js";
import {
  AcknowledgeRoomClosureInput,
  CloseOwnedChatRoomInput,
  CloseRoomByModerationInput,
  DeleteChatMessageInput,
} from "./contracts.js";

const DELETED_MESSAGE_PREVIEW = "삭제된 메시지입니다.";

type DeleteActorKind = "author" | "roomOwner" | "platformAdmin";
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

export type MessageStorageTarget = {bucket: string | null; prefix: string};

export function messageStorageTargets(
  roomID: string,
  messageID: string,
  data: FirebaseFirestore.DocumentData,
): MessageStorageTarget[] {
  const attachments = Array.isArray(data.attachments) ? data.attachments : [];
  const expected = `rooms/${roomID}/messages/${messageID}`;
  const targets = new Map<string, MessageStorageTarget>();
  for (const attachment of attachments) {
    if (!attachment || typeof attachment !== "object") continue;
    for (const [pathField, bucketField] of [
      ["pathThumb", "bucketThumb"],
      ["pathOriginal", "bucketOriginal"],
    ] as const) {
      const value = attachment[pathField];
      if (typeof value !== "string" ||
          (value !== expected && !value.startsWith(`${expected}/`))) continue;
      const bucketValue = attachment[bucketField];
      const bucket = typeof bucketValue === "string" && bucketValue.length > 0 ?
        bucketValue : null;
      targets.set(bucket ?? "__default__", {bucket, prefix: expected});
    }
  }
  return [...targets.values()];
}

export function messageCleanupJobID(roomID: string, messageID: string): string {
  return createHash("sha256").update(`${roomID}:${messageID}`).digest("hex");
}

function messageTargetID(roomID: string, messageID: string): string {
  return `${roomID}:${messageID}`;
}

function cleanupStatusForEvidenceGuard(
  guard: FirebaseFirestore.DocumentData | undefined,
): "awaitingEvidence" | "pending" {
  if (guard?.guardWinner !== "reportFirst") return "pending";
  return guard.evidenceState === "available" || guard.evidenceState === "failed" ?
    "pending" : "awaitingEvidence";
}

async function deleteActor(
  actorUID: string,
  room: FirebaseFirestore.DocumentData,
  message: FirebaseFirestore.DocumentData,
  admin: FirebaseFirestore.DocumentData | undefined,
): Promise<DeleteActorKind> {
  if (message.senderUID === actorUID) {
    await assertAccountCapability(actorUID, "deleteOwnUGC");
    return "author";
  }
  if (room.creatorUID === actorUID) {
    await assertAccountCapability(actorUID, "moderateOwnedRoom");
    return "roomOwner";
  }
  if (activePlatformAdmin(admin)) {
    await assertAccountCapability(actorUID, "readAppContent");
    return "platformAdmin";
  }
  throw new HttpsError("permission-denied", "메시지 삭제 권한이 없습니다.");
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
  const [roomSnapshot, messageSnapshot, adminSnapshot] = await Promise.all([
    roomRef.get(),
    messageRef.get(),
    adminRef.get(),
  ]);
  if (!roomSnapshot.exists || !roomSnapshot.data()) {
    throw new HttpsError("not-found", "채팅방을 찾을 수 없습니다.");
  }
  if (!messageSnapshot.exists || !messageSnapshot.data()) {
    throw new HttpsError("not-found", "메시지를 찾을 수 없습니다.");
  }
  const actorKind = await deleteActor(
    actorUID,
    roomSnapshot.data()!,
    messageSnapshot.data()!,
    adminSnapshot.data(),
  );
  if (actorKind !== "author" && !input.reasonCode) {
    throw new HttpsError("invalid-argument", "관리 목적 삭제에는 reasonCode가 필요합니다.");
  }
  if (actorKind === "platformAdmin") {
    const authTimeMillis = typeof authTime === "number" ? authTime * 1_000 : NaN;
    if (!Number.isFinite(authTimeMillis) || now.getTime() - authTimeMillis > 5 * 60_000 ||
      authTimeMillis > now.getTime() + 30_000) {
      throw new HttpsError("unauthenticated", "관리자 작업을 위해 다시 로그인해 주세요.");
    }
  }

  const jobRef = firestore.collection("chatMessageCleanupJobs")
    .doc(messageCleanupJobID(input.roomID, input.messageID));
  const incidentID = messageIncidentID(input.roomID, input.messageID);
  const guardRef = firestore.collection("moderationMessageGuards").doc(incidentID);
  return firestore.runTransaction(async (transaction) => {
    const [audit, currentRoom, currentMessage, currentJob, currentGuard] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(roomRef),
      transaction.get(messageRef),
      transaction.get(jobRef),
      transaction.get(guardRef),
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
    if (message.seq !== input.expectedSeq) {
      throw new HttpsError("aborted", "메시지 상태가 변경됐습니다.", {
        errorCode: "STALE_MESSAGE_SEQ",
      });
    }
    const nowTimestamp = Timestamp.fromDate(now);
    const guardData = currentGuard.data();
    const cleanupStatus = cleanupStatusForEvidenceGuard(guardData);
    const result = {
      messageID: input.messageID,
      seq: input.expectedSeq,
      isDeleted: true,
      cleanupStatus: currentJob.exists && currentJob.get("status") === "completed" ?
        "completed" : currentJob.exists && currentJob.get("status") === "awaitingEvidence" ?
          "awaitingEvidence" : cleanupStatus,
      deduplicated: message.isDeleted === true,
      deletedAt: message.deletedAt instanceof Timestamp ?
        message.deletedAt.toDate().toISOString() : now.toISOString(),
    };
    if (message.isDeleted !== true) {
      const storageTargets = messageStorageTargets(input.roomID, input.messageID, message);
      transaction.update(messageRef, {
        isDeleted: true,
        deletedAt: nowTimestamp,
        deletionPresentation: actorKind === "platformAdmin" ?
          "moderationRemoved" : "deleted",
        moderationVisibilityState: "deleted",
        msg: FieldValue.delete(),
        attachments: FieldValue.delete(),
        sharedContent: FieldValue.delete(),
        replyPreview: FieldValue.delete(),
        searchNormalized: FieldValue.delete(),
        searchChars: FieldValue.delete(),
        searchNgrams2: FieldValue.delete(),
        searchIndexVersion: FieldValue.delete(),
        senderEmail: FieldValue.delete(),
        senderNickname: FieldValue.delete(),
        senderAvatarPath: FieldValue.delete(),
        messageType: FieldValue.delete(),
        isFailed: FieldValue.delete(),
      });
      if (currentRoom.get("lastMessageSeq") === input.expectedSeq) {
        transaction.update(roomRef, {
          lastMessage: DELETED_MESSAGE_PREVIEW,
          updatedAt: nowTimestamp,
        });
      }
      if (currentRoom.get("activeAnnouncementID") === input.messageID) {
        transaction.update(roomRef, {
          activeAnnouncementID: FieldValue.delete(),
          activeAnnouncement: FieldValue.delete(),
          announcementUpdatedAt: nowTimestamp,
        });
      }
      if (!currentJob.exists) {
        transaction.create(jobRef, {
          schemaVersion: 2,
          roomID: input.roomID,
          messageID: input.messageID,
          expectedSeq: input.expectedSeq,
          storageTargets,
          storagePrefixes: storageTargets
            .filter((target) => target.bucket === null)
            .map((target) => target.prefix),
          status: cleanupStatus,
          attempt: 0,
          nextAttemptAt: cleanupStatus === "awaitingEvidence" ? null : nowTimestamp,
          leaseExpiresAt: null,
          lastErrorCode: null,
          createdAt: nowTimestamp,
          updatedAt: nowTimestamp,
          expiresAt: null,
        });
      }
    }
    if (!currentGuard.exists) {
      transaction.create(guardRef, {
        schemaVersion: 1,
        roomID: input.roomID,
        messageID: input.messageID,
        contentState: "deleted",
        guardWinner: "deleteFirst",
        evidenceState: "none",
        bundleID: null,
        reviewRevision: null,
        updatedAt: nowTimestamp,
      });
    } else if (guardData?.contentState !== "deleted") {
      transaction.update(guardRef, {
        contentState: "deleted",
        updatedAt: nowTimestamp,
      });
    }
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
    const [audit, room, existingJob] = await Promise.all([
      transaction.get(auditRef),
      transaction.get(roomRef),
      transaction.get(jobRef),
    ]);
    if (audit.exists && audit.data()) {
      return assertAuditReplay(audit.data()!, {
        action,
        targetType: "room",
        targetID: input.roomID,
        requestID: input.clientRequestID,
      });
    }
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
  await assertAccountCapability(actorUID, "moderateOwnedRoom");
  const room = await firestore.collection("Rooms").doc(input.roomID).get();
  if (!room.exists || room.get("creatorUID") !== actorUID) {
    throw new HttpsError("permission-denied", "방 생성자 권한이 필요합니다.");
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
