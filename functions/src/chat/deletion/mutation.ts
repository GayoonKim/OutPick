/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

const DELETION_DELIVERY_TTL_MILLIS = 7 * 24 * 60 * 60 * 1000;
export const DELETED_MESSAGE_PREVIEW = "삭제된 메시지입니다";

export type MessageStorageTarget = {bucket: string | null; prefix: string};

export type MessageDeletionTarget = {
  messageRef: DocumentReference;
  message: DocumentSnapshot;
  cleanupRef: DocumentReference;
  cleanup: DocumentSnapshot;
  guardRef: DocumentReference;
  guard: DocumentSnapshot;
};

export type SingleMessageDeletionResult = {
  outcome: "deleted" | "alreadyDeleted" | "legacyDeletedNormalized";
  messageID: string;
  seq: number;
  deletionRevision: number | null;
  deletedAt: Timestamp;
  cleanupStatus: string;
  cleanupJobID: string;
  deliveryJobID: string | null;
};

export type RoomMessageDeletionBatchResult = {
  deletedCount: number;
  normalizedCount: number;
  fromRevision: number | null;
  toRevision: number | null;
  deliveryJobID: string | null;
};

function positiveSafeInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : null;
}

function nonNegativeSafeInteger(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function messageSequence(message: DocumentSnapshot): number {
  const value = message.get("seq");
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error("invalid_message_seq");
  }
  return value;
}

export function messageCleanupJobID(roomID: string, messageID: string): string {
  return createHash("sha256").update(`${roomID}:${messageID}`).digest("hex");
}

export function messageDeletionDeliveryJobID(
  roomID: string,
  messageID: string,
  deletionRevision: number,
): string {
  return createHash("sha256")
    .update(`messageDeleted:${roomID}:${messageID}:${deletionRevision}`)
    .digest("hex");
}

export function deletionHeadDeliveryJobID(
  roomID: string,
  fromRevision: number,
  toRevision: number,
): string {
  return createHash("sha256")
    .update(`deletionHeadAdvanced:${roomID}:${fromRevision}:${toRevision}`)
    .digest("hex");
}

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

export function cleanupStatusForEvidenceGuard(
  guard: FirebaseFirestore.DocumentData | undefined,
): "awaitingEvidence" | "pending" {
  if (guard?.guardWinner !== "reportFirst") return "pending";
  return guard.evidenceState === "available" || guard.evidenceState === "failed" ?
    "pending" : "awaitingEvidence";
}

function copyDefinedFields(
  source: FirebaseFirestore.DocumentData,
  fields: string[],
): FirebaseFirestore.DocumentData {
  const copied: FirebaseFirestore.DocumentData = {};
  for (const field of fields) {
    if (source[field] !== undefined) copied[field] = source[field];
  }
  return copied;
}

function tombstone(
  roomID: string,
  messageID: string,
  seq: number,
  deletionRevision: number | null,
  deletedAt: Timestamp,
  source: FirebaseFirestore.DocumentData,
  anonymizesSender: boolean,
): FirebaseFirestore.DocumentData {
  const presentation = anonymizesSender ? {
    senderNickname: "알 수 없는 사용자",
    senderAnonymized: true,
    ...copyDefinedFields(source, ["sentAt", "createdAt"]),
  } : {
    senderAnonymized: false,
    ...copyDefinedFields(source, [
      "senderUID",
      "senderNickname",
      "senderAvatarPath",
      "sentAt",
      "createdAt",
      "replyPreview",
    ]),
  };
  return {
    ID: messageID,
    roomID,
    seq,
    ...presentation,
    isDeleted: true,
    ...(deletionRevision === null ? {} : {deletionRevision}),
    deletedAt,
  };
}

function writeCleanupJob(
  transaction: Transaction,
  target: MessageDeletionTarget,
  roomID: string,
  messageID: string,
  seq: number,
  now: Timestamp,
  accountDeletionRequestID: string | null,
): string {
  const status = cleanupStatusForEvidenceGuard(target.guard.data());
  if (!target.cleanup.exists) {
    const storageTargets = messageStorageTargets(roomID, messageID, target.message.data() ?? {});
    transaction.create(target.cleanupRef, {
      schemaVersion: 3,
      roomID,
      messageID,
      expectedSeq: seq,
      storageTargets,
      storagePrefixes: storageTargets
        .filter((item) => item.bucket === null)
        .map((item) => item.prefix),
      status,
      attempt: 0,
      nextAttemptAt: status === "awaitingEvidence" ? null : now,
      leaseExpiresAt: null,
      lastErrorCode: null,
      ...(accountDeletionRequestID ? {accountDeletionRequestID} : {}),
      createdAt: now,
      updatedAt: now,
      expiresAt: null,
    });
  } else if (accountDeletionRequestID) {
    transaction.set(target.cleanupRef, {
      accountDeletionRequestID,
      updatedAt: now,
    }, {merge: true});
  }
  return target.cleanup.exists && typeof target.cleanup.get("status") === "string" ?
    target.cleanup.get("status") : status;
}

function writeDeletedGuard(
  transaction: Transaction,
  target: MessageDeletionTarget,
  roomID: string,
  messageID: string,
  now: Timestamp,
): void {
  if (!target.guard.exists) {
    transaction.create(target.guardRef, {
      schemaVersion: 1,
      roomID,
      messageID,
      contentState: "deleted",
      guardWinner: "deleteFirst",
      evidenceState: "none",
      bundleID: null,
      reviewRevision: null,
      updatedAt: now,
    });
  } else if (target.guard.get("contentState") !== "deleted") {
    transaction.update(target.guardRef, {contentState: "deleted", updatedAt: now});
  }
}

function writeMessageDeliveryJob(
  transaction: Transaction,
  firestore: Firestore,
  roomID: string,
  messageID: string,
  seq: number,
  deletionRevision: number,
  now: Timestamp,
): string {
  const deliveryJobID = messageDeletionDeliveryJobID(roomID, messageID, deletionRevision);
  transaction.set(firestore.collection("chatMessageDeletionDeliveryJobs").doc(deliveryJobID), {
    schemaVersion: 1,
    roomID,
    messageID,
    seq,
    deletionRevision,
    eventKind: "messageDeleted",
    status: "pending",
    attempt: 0,
    nextAttemptAt: now,
    leaseToken: null,
    leaseExpiresAt: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + DELETION_DELIVERY_TTL_MILLIS),
  });
  return deliveryJobID;
}

export function applySingleMessageDeletionMutation(
  transaction: Transaction,
  firestore: Firestore,
  roomRef: DocumentReference,
  room: DocumentSnapshot,
  target: MessageDeletionTarget,
  roomID: string,
  messageID: string,
  now: Timestamp,
  accountDeletionRequestID: string | null = null,
): SingleMessageDeletionResult {
  const data = target.message.data();
  if (!room.exists || !target.message.exists || !data) {
    throw new Error("message_deletion_snapshot_missing");
  }
  const seq = messageSequence(target.message);
  const alreadyDeleted = data.isDeleted === true;
  const priorRevision = positiveSafeInteger(data.deletionRevision);
  const deletedAt = data.deletedAt instanceof Timestamp ? data.deletedAt : now;
  let revision = priorRevision;
  let deliveryJobID: string | null = null;

  if (!alreadyDeleted) {
    revision = nonNegativeSafeInteger(room.get("messageDeletionRevision")) + 1;
    const roomPatch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      messageDeletionRevision: revision,
      updatedAt: now,
    };
    if (room.get("lastMessageSeq") === seq) roomPatch.lastMessage = DELETED_MESSAGE_PREVIEW;
    if (room.get("activeAnnouncementID") === messageID) {
      roomPatch.activeAnnouncementID = FieldValue.delete();
      roomPatch.activeAnnouncement = FieldValue.delete();
      roomPatch.announcementUpdatedAt = now;
    }
    transaction.update(roomRef, roomPatch);
    deliveryJobID = writeMessageDeliveryJob(
      transaction, firestore, roomID, messageID, seq, revision, now,
    );
  } else if (room.get("lastMessageSeq") === seq || room.get("activeAnnouncementID") === messageID) {
    const roomPatch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {updatedAt: now};
    if (room.get("lastMessageSeq") === seq) roomPatch.lastMessage = DELETED_MESSAGE_PREVIEW;
    if (room.get("activeAnnouncementID") === messageID) {
      roomPatch.activeAnnouncementID = FieldValue.delete();
      roomPatch.activeAnnouncement = FieldValue.delete();
      roomPatch.announcementUpdatedAt = now;
    }
    transaction.update(roomRef, roomPatch);
  }

  transaction.set(target.messageRef, tombstone(
    roomID,
    messageID,
    seq,
    revision,
    deletedAt,
    data,
    accountDeletionRequestID !== null,
  ));
  const nextCleanupStatus = writeCleanupJob(
    transaction, target, roomID, messageID, seq, now, accountDeletionRequestID,
  );
  writeDeletedGuard(transaction, target, roomID, messageID, now);

  return {
    outcome: !alreadyDeleted ? "deleted" : priorRevision === null ?
      "legacyDeletedNormalized" : "alreadyDeleted",
    messageID,
    seq,
    deletionRevision: revision,
    deletedAt,
    cleanupStatus: nextCleanupStatus,
    cleanupJobID: target.cleanupRef.id,
    deliveryJobID,
  };
}

export function applyRoomMessageDeletionBatchMutation(
  transaction: Transaction,
  firestore: Firestore,
  roomRef: DocumentReference,
  room: DocumentSnapshot,
  targets: MessageDeletionTarget[],
  roomID: string,
  now: Timestamp,
  accountDeletionRequestID: string,
): RoomMessageDeletionBatchResult {
  const ordered = [...targets].sort((lhs, rhs) => {
    const seqOrder = messageSequence(lhs.message) - messageSequence(rhs.message);
    return seqOrder === 0 ? lhs.message.id.localeCompare(rhs.message.id) : seqOrder;
  });
  const visible = ordered.filter((target) => target.message.get("isDeleted") !== true);
  const fromRevision = room.exists && visible.length > 0 ?
    nonNegativeSafeInteger(room.get("messageDeletionRevision")) + 1 : null;
  const toRevision = fromRevision === null ? null : fromRevision + visible.length - 1;
  const revisionByPath = new Map<string, number>();
  if (fromRevision !== null) {
    visible.forEach((target, index) => revisionByPath.set(target.messageRef.path, fromRevision + index));
  }

  let normalizeCount = 0;
  for (const target of ordered) {
    const data = target.message.data();
    if (!target.message.exists || !data) continue;
    const messageID = target.message.id;
    const seq = messageSequence(target.message);
    const assignedRevision = revisionByPath.get(target.messageRef.path) ??
      positiveSafeInteger(target.message.get("deletionRevision"));
    const deletedAt = target.message.get("deletedAt") instanceof Timestamp ?
      target.message.get("deletedAt") : now;
    if (target.message.get("isDeleted") === true) normalizeCount += 1;
    transaction.set(target.messageRef, tombstone(
      roomID,
      messageID,
      seq,
      assignedRevision ?? null,
      deletedAt,
      data,
      true,
    ));
    writeCleanupJob(
      transaction, target, roomID, messageID, seq, now, accountDeletionRequestID,
    );
    writeDeletedGuard(transaction, target, roomID, messageID, now);
  }

  const deletedIDs = new Set(ordered.map((target) => target.message.id));
  const deletedSeqs = new Set(ordered.map((target) => messageSequence(target.message)));
  const roomPatch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
  if (toRevision !== null) roomPatch.messageDeletionRevision = toRevision;
  if (deletedSeqs.has(room.get("lastMessageSeq"))) roomPatch.lastMessage = DELETED_MESSAGE_PREVIEW;
  if (deletedIDs.has(room.get("activeAnnouncementID"))) {
    roomPatch.activeAnnouncementID = FieldValue.delete();
    roomPatch.activeAnnouncement = FieldValue.delete();
    roomPatch.announcementUpdatedAt = now;
  }
  if (room.exists && Object.keys(roomPatch).length > 0) {
    roomPatch.updatedAt = now;
    transaction.update(roomRef, roomPatch);
  }

  let deliveryJobID: string | null = null;
  if (fromRevision !== null && toRevision !== null) {
    deliveryJobID = deletionHeadDeliveryJobID(roomID, fromRevision, toRevision);
    transaction.set(firestore.collection("chatMessageDeletionDeliveryJobs").doc(deliveryJobID), {
      schemaVersion: 1,
      roomID,
      fromRevision,
      toRevision,
      eventKind: "deletionHeadAdvanced",
      status: "pending",
      attempt: 0,
      nextAttemptAt: now,
      leaseToken: null,
      leaseExpiresAt: null,
      createdAt: now,
      updatedAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + DELETION_DELIVERY_TTL_MILLIS),
    });
  }
  return {
    deletedCount: visible.length,
    normalizedCount: normalizeCount,
    fromRevision,
    toRevision,
    deliveryJobID,
  };
}
