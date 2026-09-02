/* eslint-disable require-jsdoc, max-len */
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {
  CHAT_MEDIA_DELIVERY_RETENTION_MILLIS,
  CHAT_MEDIA_TERMINAL_RETENTION_MILLIS,
  isChatMediaKind,
  type ChatMediaKind,
} from "./contracts.js";

type ManifestEntry = {
  attachmentID: string;
  displayBucket: string;
  displayPath: string;
  displayGeneration: string;
  displayBytes: number;
  displayContentType: string;
  thumbnailBucket: string;
  thumbnailPath: string;
  thumbnailGeneration: string;
  thumbnailBytes: number;
  thumbnailContentType: string;
};

type ReadyResult = {
  published: boolean;
  duplicate: boolean;
  reason: string;
  roomID: string;
  messageID: string;
  seq: number | null;
  quarantineBucket: string;
  quarantinePaths: string[];
  readyObjects: Array<{bucket: string; path: string}>;
};

export async function publishCompletedMediaUpload(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  nowMillis: number;
}): Promise<ReadyResult> {
  return input.firestore.runTransaction(async (transaction) => {
    const upload = await transaction.get(input.uploadRef);
    const data = upload.data() ?? {};
    const roomID = boundedID(data.roomID);
    const messageID = boundedID(data.messageID ?? data.uploadID);
    const kind = data.kind;
    const manifest = normalizedManifest(data.normalizedManifest);
    const quarantinePaths = stringArray(data.quarantinePaths);
    const quarantineBucket = boundedString(data.quarantineBucket);
    const readyObjects = manifest.flatMap((entry) => [
      {bucket: entry.displayBucket, path: entry.displayPath},
      {bucket: entry.thumbnailBucket, path: entry.thumbnailPath},
    ]);
    const base = {
      roomID,
      messageID,
      quarantineBucket,
      quarantinePaths,
      readyObjects,
    };
    if (!upload.exists || data.contractVersion !== 2 || !roomID || !messageID ||
        !isChatMediaKind(kind)) {
      return {...base, published: false, duplicate: false, reason: "invalid_contract", seq: null};
    }
    if (data.processingStatus === "ready" && Number.isInteger(data.seq)) {
      return {
        ...base,
        published: true,
        duplicate: true,
        reason: "already_ready",
        seq: Number(data.seq),
      };
    }
    if (data.processingStatus !== "processing" ||
        typeof data.leaseToken !== "string" || !data.leaseToken ||
        manifest.length !== Number(data.attachmentCount) || manifest.length < 1) {
      return {...base, published: false, duplicate: false, reason: "stale_or_invalid_completion", seq: null};
    }
    if (!boundedID(data.senderUID) || !boundedID(data.moderationPrincipalID) ||
        !quarantineBucket) {
      return await failCompletion(transaction, input, data, base, "media_identity_invalid");
    }
    if (!manifestMatchesReservation(manifest, roomID, messageID, kind, data.attachmentIDs)) {
      return await failCompletion(transaction, input, data, base, "normalized_manifest_invalid");
    }

    const roomRef = input.firestore.collection("Rooms").doc(roomID);
    const messageRef = roomRef.collection("Messages").doc(messageID);
    const memberRef = roomRef.collection("members").doc(String(data.senderUID ?? ""));
    const banRef = roomRef.collection("bans").doc(String(data.moderationPrincipalID ?? ""));
    const profileRef = input.firestore.collection("userPublicProfiles")
      .doc(String(data.senderUID ?? ""));
    const deliveryRef = input.firestore.collection("chatMediaDeliveryJobs")
      .doc(`${roomID}_${messageID}`);
    const processingSlotRef = typeof data.processingSlotID === "string" && data.processingSlotID ?
      input.firestore.collection("chatMediaProcessingSlots").doc(data.processingSlotID) : null;
    const principalSlotRef = typeof data.principalSlotID === "string" && data.principalSlotID ?
      input.firestore.collection("chatMediaPrincipalUploadSlots").doc(data.principalSlotID) : null;

    // Firestore transaction은 모든 read가 write보다 먼저 와야 한다.
    const room = await transaction.get(roomRef);
    const message = await transaction.get(messageRef);
    const member = await transaction.get(memberRef);
    const ban = await transaction.get(banRef);
    const profile = await transaction.get(profileRef);
    const delivery = await transaction.get(deliveryRef);
    const processingSlot = processingSlotRef ? await transaction.get(processingSlotRef) : null;
    const principalSlot = principalSlotRef ? await transaction.get(principalSlotRef) : null;

    if (message.exists) {
      const existing = message.data() ?? {};
      if (existing.mediaUploadPath === input.uploadRef.path && Number.isInteger(existing.seq)) {
        return {
          ...base,
          published: true,
          duplicate: true,
          reason: "message_already_created",
          seq: Number(existing.seq),
        };
      }
      return await failCompletionAfterReads(
        transaction, input, data, base, processingSlotRef, processingSlot,
        principalSlotRef, principalSlot, "message_id_conflict"
      );
    }
    if (delivery.exists) {
      return await failCompletionAfterReads(
        transaction, input, data, base, processingSlotRef, processingSlot,
        principalSlotRef, principalSlot, "delivery_job_conflict"
      );
    }
    if (!room.exists || room.data()?.isClosed === true ||
        (room.data()?.lifecycleStatus && room.data()?.lifecycleStatus !== "active") ||
        !member.exists || ban.data()?.isActive === true || !profile.exists ||
        !boundedString(profile.data()?.nickname).trim()) {
      return await failCompletionAfterReads(
        transaction, input, data, base, processingSlotRef, processingSlot,
        principalSlotRef, principalSlot, "room_access_revoked"
      );
    }

    const currentSeq = Number.isInteger(room.data()?.seq) ? Number(room.data()?.seq) : 0;
    const seq = currentSeq + 1;
    // 역할 이벤트 활성화 전 legacy Room은 timeline seq와 unread seq가 동일하다.
    const currentUnreadMessageSeq = Number.isInteger(room.data()?.unreadMessageSeq) ?
      Number(room.data()?.unreadMessageSeq) : currentSeq;
    const unreadMessageSeq = currentUnreadMessageSeq + 1;
    const sentAt = Timestamp.fromMillis(input.nowMillis);
    const attachments = buildAttachments(kind, manifest, data.technicalValidationResult);
    const nickname = boundedString(profile.data()?.nickname).trim().slice(0, 80);
    const avatar = boundedString(
      profile.data()?.avatarThumbPath ?? profile.data()?.avatarOriginalPath
    );
    const messageData = {
      ID: messageID,
      roomID,
      roomName: roomID,
      senderUID: String(data.senderUID),
      senderNickname: nickname,
      ...(avatar ? {senderAvatarPath: avatar} : {}),
      msg: "",
      message: "",
      sentAt: sentAt.toDate().toISOString(),
      messageType: kind === "images" ? "Image" : "Video",
      attachments,
      replyPreview: null,
      isFailed: false,
      isDeleted: false,
      moderationVisibilityState: "visible",
      mediaContractVersion: 2,
      mediaUploadPath: input.uploadRef.path,
      readyAttachmentIDs: manifest.map((entry) => entry.attachmentID),
      seq,
      unreadMessageSeq,
    };

    transaction.create(messageRef, messageData);
    attachments.forEach((attachment, index) => {
      transaction.set(roomRef.collection("mediaIndex").doc(`${messageID}_${index}`), {
        roomID,
        messageID,
        idx: index,
        seq,
        senderUID: String(data.senderUID),
        type: attachment.type,
        thumbURL: attachment.pathThumb,
        originalURL: attachment.pathOriginal,
        bucketThumb: attachment.bucketThumb,
        bucketOriginal: attachment.bucketOriginal,
        width: attachment.w,
        height: attachment.h,
        bytesOriginal: attachment.bytesOriginal,
        generationOriginal: attachment.generationOriginal,
        contentTypeOriginal: attachment.contentTypeOriginal,
        mediaFormat: attachment.mediaFormat,
        animated: attachment.animated,
        ...(typeof attachment.duration === "number" ? {duration: attachment.duration} : {}),
        isDeleted: false,
        sentAt,
      });
    });
    transaction.set(roomRef, {
      seq,
      unreadMessageSeq,
      lastMessage: kind === "images" ?
        (attachments.length === 1 ? "[사진]" : `[사진 ${attachments.length}장]`) : "[동영상]",
      lastMessageAt: sentAt,
      lastMessageSeq: seq,
    }, {merge: true});
    transaction.create(deliveryRef, {
      schemaVersion: 1,
      roomID,
      messageID,
      seq,
      eventKind: kind === "images" ? "receiveImages" : "receiveVideo",
      status: "pending",
      attempt: 0,
      nextAttemptAt: sentAt,
      leaseToken: null,
      leaseExpiresAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        input.nowMillis + CHAT_MEDIA_DELIVERY_RETENTION_MILLIS
      ),
    });
    releaseOwnedSlots(
      transaction, input, data, processingSlotRef, processingSlot,
      principalSlotRef, principalSlot
    );
    transaction.update(input.uploadRef, {
      processingStatus: "ready",
      seq,
      messageID,
      retryable: false,
      failureCode: null,
      leaseToken: null,
      leaseExpiresAt: null,
      processingSlotID: null,
      executionName: null,
      nextAttemptAt: null,
      cleanupStatus: "pending",
      terminalAt: sentAt,
      expiresAt: Timestamp.fromMillis(
        input.nowMillis + CHAT_MEDIA_TERMINAL_RETENTION_MILLIS
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {...base, published: true, duplicate: false, reason: "ready", seq};
  });
}

async function failCompletion(
  transaction: Transaction,
  input: {firestore: Firestore; uploadRef: DocumentReference; nowMillis: number},
  data: DocumentData,
  base: Omit<ReadyResult, "published" | "duplicate" | "reason" | "seq">,
  failureCode: string
): Promise<ReadyResult> {
  const processingSlotRef = typeof data.processingSlotID === "string" && data.processingSlotID ?
    input.firestore.collection("chatMediaProcessingSlots").doc(data.processingSlotID) : null;
  const principalSlotRef = typeof data.principalSlotID === "string" && data.principalSlotID ?
    input.firestore.collection("chatMediaPrincipalUploadSlots").doc(data.principalSlotID) : null;
  const processingSlot = processingSlotRef ? await transaction.get(processingSlotRef) : null;
  const principalSlot = principalSlotRef ? await transaction.get(principalSlotRef) : null;
  return failCompletionAfterReads(
    transaction, input, data, base, processingSlotRef, processingSlot,
    principalSlotRef, principalSlot, failureCode
  );
}

async function failCompletionAfterReads(
  transaction: Transaction,
  input: {firestore: Firestore; uploadRef: DocumentReference; nowMillis: number},
  data: DocumentData,
  base: Omit<ReadyResult, "published" | "duplicate" | "reason" | "seq">,
  processingSlotRef: DocumentReference | null,
  processingSlot: FirebaseFirestore.DocumentSnapshot | null,
  principalSlotRef: DocumentReference | null,
  principalSlot: FirebaseFirestore.DocumentSnapshot | null,
  failureCode: string
): Promise<ReadyResult> {
  releaseOwnedSlots(
    transaction, input, data, processingSlotRef, processingSlot,
    principalSlotRef, principalSlot
  );
  transaction.update(input.uploadRef, {
    processingStatus: "failed",
    retryable: false,
    failureCode,
    leaseToken: null,
    leaseExpiresAt: null,
    processingSlotID: null,
    executionName: null,
    nextAttemptAt: null,
    cleanupStatus: "pending",
    terminalAt: Timestamp.fromMillis(input.nowMillis),
    expiresAt: Timestamp.fromMillis(
      input.nowMillis + CHAT_MEDIA_TERMINAL_RETENTION_MILLIS
    ),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {...base, published: false, duplicate: false, reason: failureCode, seq: null};
}

function releaseOwnedSlots(
  transaction: Transaction,
  input: {uploadRef: DocumentReference},
  data: DocumentData,
  processingSlotRef: DocumentReference | null,
  processingSlot: FirebaseFirestore.DocumentSnapshot | null,
  principalSlotRef: DocumentReference | null,
  principalSlot: FirebaseFirestore.DocumentSnapshot | null
): void {
  if (processingSlotRef && processingSlot?.data()?.leaseToken === data.leaseToken) {
    transaction.set(processingSlotRef, {
      leaseToken: null,
      leaseOwnerUploadPath: null,
      leaseExpiresAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  if (principalSlotRef && principalSlot?.data()?.ownerUploadPath === input.uploadRef.path) {
    transaction.set(principalSlotRef, {
      ownerUploadPath: null,
      clientMutationID: null,
      leaseExpiresAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

function normalizedManifest(value: unknown): ManifestEntry[] {
  if (!Array.isArray(value)) return [];
  return value.map((raw) => {
    const entry = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    return {
      attachmentID: boundedString(entry.attachmentID),
      displayBucket: boundedString(entry.displayBucket),
      displayPath: boundedString(entry.displayPath),
      displayGeneration: boundedString(entry.displayGeneration),
      displayBytes: Number(entry.displayBytes),
      displayContentType: boundedString(entry.displayContentType).toLowerCase(),
      thumbnailBucket: boundedString(entry.thumbnailBucket),
      thumbnailPath: boundedString(entry.thumbnailPath),
      thumbnailGeneration: boundedString(entry.thumbnailGeneration),
      thumbnailBytes: Number(entry.thumbnailBytes),
      thumbnailContentType: boundedString(entry.thumbnailContentType).toLowerCase(),
    };
  });
}

function manifestMatchesReservation(
  manifest: ManifestEntry[],
  roomID: string,
  messageID: string,
  kind: ChatMediaKind,
  attachmentIDsValue: unknown
): boolean {
  const expectedIDs = stringArray(attachmentIDsValue);
  const actualIDs = manifest.map((entry) => entry.attachmentID);
  return expectedIDs.length === actualIDs.length &&
    new Set(actualIDs).size === actualIDs.length &&
    actualIDs.every((id) => expectedIDs.includes(id)) &&
    manifest.every((entry) => {
      const prefix = `rooms/${roomID}/messages/${messageID}/attachments/${entry.attachmentID}`;
      const displayTypes = kind === "video" ? ["video/mp4"] :
        ["image/jpeg", "image/png", "image/gif"];
      return entry.attachmentID && entry.displayBucket && entry.thumbnailBucket &&
        entry.displayPath === `${prefix}/display` &&
        entry.thumbnailPath === `${prefix}/thumbnail` &&
        entry.displayGeneration && entry.thumbnailGeneration &&
        Number.isSafeInteger(entry.displayBytes) && entry.displayBytes > 0 &&
        Number.isSafeInteger(entry.thumbnailBytes) && entry.thumbnailBytes > 0 &&
        displayTypes.includes(entry.displayContentType) &&
        entry.thumbnailContentType === "image/jpeg";
    });
}

function buildAttachments(
  kind: ChatMediaKind,
  manifest: ManifestEntry[],
  technicalValue: unknown
): Array<Record<string, unknown>> {
  const technical = Array.isArray(technicalValue) ? technicalValue : [];
  const byID = new Map(technical.map((raw) => {
    const item = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    return [boundedString(item.attachmentID), item];
  }));
  return manifest.map((entry, index) => {
    const detail = byID.get(entry.attachmentID) ?? {};
    const duration = Number(detail.durationSeconds);
    return {
      attachmentID: entry.attachmentID,
      type: kind === "images" ? "image" : "video",
      index,
      pathThumb: entry.thumbnailPath,
      pathOriginal: entry.displayPath,
      bucketThumb: entry.thumbnailBucket,
      bucketOriginal: entry.displayBucket,
      w: positiveInteger(detail.width),
      h: positiveInteger(detail.height),
      bytesOriginal: entry.displayBytes,
      generationOriginal: entry.displayGeneration,
      contentTypeOriginal: entry.displayContentType,
      hash: "",
      blurhash: null,
      mediaFormat: kind === "images" ? imageFormat(entry.displayContentType) : "mp4",
      animated: kind === "images" &&
        entry.displayContentType === "image/gif" &&
        detail.animated === true &&
        positiveInteger(detail.frameCount) > 1,
      ...(kind === "video" && Number.isFinite(duration) && duration >= 0 ? {duration} : {}),
    };
  });
}

function imageFormat(contentType: string): "jpeg" | "png" | "gif" {
  if (contentType === "image/png") return "png";
  if (contentType === "image/gif") return "gif";
  return "jpeg";
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter(
    (item): item is string => typeof item === "string" && item.length > 0
  ) : [];
}

function boundedID(value: unknown): string {
  const result = boundedString(value);
  return result && result.length <= 512 && !result.includes("/") ? result : "";
}

function boundedString(value: unknown): string {
  return typeof value === "string" && value.length <= 1024 ? value : "";
}

function positiveInteger(value: unknown): number {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : 0;
}
