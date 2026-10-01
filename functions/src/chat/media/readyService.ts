/* eslint-disable require-jsdoc, max-len */
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {CHAT_MEDIA_TERMINAL_RETENTION_MILLIS} from "./contracts.js";

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

/**
 * 구형 contract 2 worker completion은 새 메시지로 확정하지 않는다.
 * 실패 reservation과 남은 객체 목록을 반환해 worker slot과 Storage 정리가 수렴하게 한다.
 * @param {object} input 확정 대상 reservation, transaction 시간, lease 검증 정보
 */
export async function publishCompletedMediaUpload(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  nowMillis: number;
  expectedLeaseToken?: string;
}): Promise<ReadyResult> {
  return input.firestore.runTransaction(async (transaction) => {
    const upload = await transaction.get(input.uploadRef);
    const data = upload.data() ?? {};
    const roomID = boundedID(data.roomID);
    const messageID = boundedID(data.messageID ?? data.uploadID);
    const base = {
      roomID,
      messageID,
      quarantineBucket: boundedString(data.quarantineBucket),
      quarantinePaths: stringArray(data.quarantinePaths),
      readyObjects: readyObjects(data.normalizedManifest),
    };
    if (!upload.exists || data.contractVersion !== 2 || !roomID || !messageID) {
      return {...base, published: false, duplicate: false, reason: "invalid_contract", seq: null};
    }
    if (input.expectedLeaseToken !== undefined && data.leaseToken !== input.expectedLeaseToken) {
      return {...base, published: false, duplicate: false, reason: "stale_execution", seq: null};
    }
    if (data.processingStatus !== "processing") {
      return {
        ...base,
        published: false,
        duplicate: false,
        reason: "legacy_media_contract_disabled",
        seq: null,
      };
    }

    await releaseOwnedSlots(transaction, input, data);
    transaction.update(input.uploadRef, {
      processingStatus: "failed",
      retryable: false,
      failureCode: "legacy_media_contract_disabled",
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
    return {
      ...base,
      published: false,
      duplicate: false,
      reason: "legacy_media_contract_disabled",
      seq: null,
    };
  });
}

async function releaseOwnedSlots(
  transaction: Transaction,
  input: {firestore: Firestore; uploadRef: DocumentReference},
  data: DocumentData
): Promise<void> {
  const processingSlotRef = typeof data.processingSlotID === "string" && data.processingSlotID ?
    input.firestore.collection("chatMediaProcessingSlots").doc(data.processingSlotID) : null;
  const principalSlotRef = typeof data.principalSlotID === "string" && data.principalSlotID ?
    input.firestore.collection("chatMediaPrincipalUploadSlots").doc(data.principalSlotID) : null;
  const processingSlot = processingSlotRef ? await transaction.get(processingSlotRef) : null;
  const principalSlot = principalSlotRef ? await transaction.get(principalSlotRef) : null;

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

function readyObjects(value: unknown): Array<{bucket: string; path: string}> {
  if (!Array.isArray(value)) return [];
  return value.flatMap((raw) => {
    const entry = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
    return [
      {bucket: boundedString(entry.displayBucket), path: boundedString(entry.displayPath)},
      {bucket: boundedString(entry.thumbnailBucket), path: boundedString(entry.thumbnailPath)},
    ].filter((object) => object.bucket && object.path);
  });
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
