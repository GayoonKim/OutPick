/* eslint-disable require-jsdoc, max-len */
import {randomUUID} from "node:crypto";
import {
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {
  CHAT_MEDIA_AUTOMATIC_ATTEMPTS,
  CHAT_MEDIA_EXECUTION_LEASE_MILLIS,
  CHAT_MEDIA_TERMINAL_RETENTION_MILLIS,
  isChatMediaKind,
  processingSlotIDs,
  type ChatMediaKind,
} from "./contracts.js";

type ClaimResult =
  | {claimed: true; leaseToken: string; slotID: string; kind: ChatMediaKind}
  | {claimed: false; reason: string; duplicate?: boolean};

type ReconcileResult = {
  changed: boolean;
  terminal: boolean;
  quarantinePaths: string[];
  reason: string;
};

function millis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" && "toMillis" in value &&
      typeof value.toMillis === "function") {
    return value.toMillis();
  }
  return null;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter(
    (item): item is string => typeof item === "string" && item.length > 0
  ) : [];
}

async function slotIsOwned(
  transaction: Transaction,
  ref: DocumentReference,
  leaseToken: string | null
): Promise<boolean> {
  const snapshot = await transaction.get(ref);
  if (!snapshot.exists) return false;
  return Boolean(leaseToken) && snapshot.data()?.leaseToken === leaseToken;
}

function releaseSlot(
  transaction: Transaction,
  ref: DocumentReference
): void {
  transaction.set(ref, {
    leaseToken: null,
    leaseOwnerUploadPath: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function principalSlotIfOwned(
  transaction: Transaction,
  firestore: Firestore,
  principalSlotID: unknown,
  uploadPath: string
): Promise<DocumentReference | null> {
  if (typeof principalSlotID !== "string" || !principalSlotID) return null;
  const ref = firestore.collection("chatMediaPrincipalUploadSlots")
    .doc(principalSlotID);
  const snapshot = await transaction.get(ref);
  if (!snapshot.exists || snapshot.data()?.ownerUploadPath !== uploadPath) return null;
  return ref;
}

function releasePrincipalSlot(
  transaction: Transaction,
  ref: DocumentReference
): void {
  transaction.set(ref, {
    ownerUploadPath: null,
    clientMutationID: null,
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function claimMediaUploadForExecution(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  projectID: string;
  nowMillis: number;
  leaseToken?: string;
}): Promise<ClaimResult> {
  const token = input.leaseToken ?? randomUUID();
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    if (!snapshot.exists) return {claimed: false, reason: "not_found"};
    const data = snapshot.data() ?? {};
    if (data.contractVersion !== 2 || !isChatMediaKind(data.kind)) {
      return {claimed: false, reason: "invalid_contract"};
    }
    if (data.processingStatus === "processing") {
      const leaseExpiresAt = millis(data.leaseExpiresAt) ?? 0;
      if (leaseExpiresAt > input.nowMillis &&
          typeof data.leaseToken === "string" &&
          typeof data.processingSlotID === "string") {
        return {
          claimed: false,
          reason: "already_claimed",
          duplicate: true,
        };
      }
    }
    if (data.processingStatus !== "queued") {
      return {claimed: false, reason: "not_queued"};
    }
    const deadline = millis(data.processingDeadlineAt) ?? 0;
    if (deadline <= input.nowMillis) {
      return {claimed: false, reason: "deadline_expired"};
    }
    const nextAttemptAt = millis(data.nextAttemptAt);
    if (nextAttemptAt !== null && nextAttemptAt > input.nowMillis) {
      return {claimed: false, reason: "retry_not_due"};
    }
    const attempt = Number.isInteger(data.processingAttempt) ?
      Number(data.processingAttempt) : 0;
    if (attempt >= CHAT_MEDIA_AUTOMATIC_ATTEMPTS) {
      return {claimed: false, reason: "attempts_exhausted"};
    }

    let chosen: {id: string; ref: DocumentReference} | null = null;
    for (const slotID of processingSlotIDs(input.projectID, data.kind)) {
      const ref = input.firestore.collection("chatMediaProcessingSlots").doc(slotID);
      const slot = await transaction.get(ref);
      const leaseExpiresAt = millis(slot.data()?.leaseExpiresAt) ?? 0;
      if (!slot.exists || !slot.data()?.leaseToken || leaseExpiresAt <= input.nowMillis) {
        chosen = {id: slotID, ref};
        break;
      }
    }
    if (!chosen) return {claimed: false, reason: "capacity_exhausted"};

    const leaseExpiresAt = Timestamp.fromMillis(
      input.nowMillis + CHAT_MEDIA_EXECUTION_LEASE_MILLIS
    );
    transaction.set(chosen.ref, {
      kind: data.kind,
      leaseToken: token,
      leaseOwnerUploadPath: input.uploadRef.path,
      leaseExpiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.update(input.uploadRef, {
      processingStatus: "processing",
      processingAttempt: attempt + 1,
      leaseToken: token,
      leaseExpiresAt,
      processingSlotID: chosen.id,
      executionName: null,
      nextAttemptAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {claimed: true, leaseToken: token, slotID: chosen.id, kind: data.kind};
  });
}

export async function recordMediaExecutionName(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  leaseToken: string;
  executionName: string;
}): Promise<boolean> {
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    const data = snapshot.data();
    if (!snapshot.exists || data?.processingStatus !== "processing" ||
        data.leaseToken !== input.leaseToken) return false;
    transaction.update(input.uploadRef, {
      executionName: input.executionName,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

export async function settleMediaDispatchFailure(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  leaseToken: string;
  nowMillis: number;
  failureCode: string;
}): Promise<ReconcileResult> {
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    const data = snapshot.data() ?? {};
    if (!snapshot.exists || data.processingStatus !== "processing" ||
        data.leaseToken !== input.leaseToken) {
      return {changed: false, terminal: false, quarantinePaths: [], reason: "stale_claim"};
    }
    const attempt = Number(data.processingAttempt) || 0;
    const deadline = millis(data.processingDeadlineAt) ?? 0;
    const slotID = typeof data.processingSlotID === "string" ? data.processingSlotID : null;
    const slotRef = slotID ?
      input.firestore.collection("chatMediaProcessingSlots").doc(slotID) : null;
    const ownsSlot = slotRef ? await slotIsOwned(
      transaction, slotRef, input.leaseToken
    ) : false;
    const retry = attempt < CHAT_MEDIA_AUTOMATIC_ATTEMPTS && deadline > input.nowMillis;
    const principalRef = retry ? null : await principalSlotIfOwned(
      transaction, input.firestore, data.principalSlotID, input.uploadRef.path
    );
    if (slotRef && ownsSlot) releaseSlot(transaction, slotRef);
    if (retry) {
      transaction.update(input.uploadRef, {
        processingStatus: "queued",
        dispatchGeneration: FieldValue.increment(1),
        leaseToken: null,
        leaseExpiresAt: null,
        processingSlotID: null,
        executionName: null,
        retryable: true,
        failureCode: input.failureCode,
        nextAttemptAt: Timestamp.fromMillis(input.nowMillis + attempt * 30_000),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {changed: true, terminal: false, quarantinePaths: [], reason: "retry_queued"};
    }
    if (principalRef) releasePrincipalSlot(transaction, principalRef);
    transaction.update(input.uploadRef, terminalFields(
      "failed", input.failureCode, input.nowMillis
    ));
    return {
      changed: true,
      terminal: true,
      quarantinePaths: stringArray(data.quarantinePaths),
      reason: "failed",
    };
  });
}

export async function reconcileStaleMediaUpload(input: {
  firestore: Firestore;
  uploadRef: DocumentReference;
  nowMillis: number;
}): Promise<ReconcileResult> {
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(input.uploadRef);
    if (!snapshot.exists) {
      return {changed: false, terminal: false, quarantinePaths: [], reason: "not_found"};
    }
    const data = snapshot.data() ?? {};
    const status = data.processingStatus;
    if (status === "uploading") {
      if ((millis(data.uploadExpiresAt) ?? millis(data.expiresAt) ?? 0) > input.nowMillis) {
        return {changed: false, terminal: false, quarantinePaths: [], reason: "not_due"};
      }
      const principalRef = await principalSlotIfOwned(
        transaction, input.firestore, data.principalSlotID, input.uploadRef.path
      );
      if (principalRef) releasePrincipalSlot(transaction, principalRef);
      transaction.update(input.uploadRef, terminalFields(
        "expired", "upload_expired", input.nowMillis
      ));
      return terminalResult(data, "upload_expired");
    }
    if (status === "queued") {
      if ((millis(data.processingDeadlineAt) ?? 0) > input.nowMillis) {
        return {changed: false, terminal: false, quarantinePaths: [], reason: "not_due"};
      }
      const principalRef = await principalSlotIfOwned(
        transaction, input.firestore, data.principalSlotID, input.uploadRef.path
      );
      if (principalRef) releasePrincipalSlot(transaction, principalRef);
      transaction.update(input.uploadRef, terminalFields(
        "expired", "processing_deadline_exceeded", input.nowMillis
      ));
      return terminalResult(data, "processing_deadline_exceeded");
    }
    if (status !== "processing" ||
        (millis(data.leaseExpiresAt) ?? 0) > input.nowMillis) {
      return {changed: false, terminal: false, quarantinePaths: [], reason: "not_due"};
    }
    const leaseToken = typeof data.leaseToken === "string" ? data.leaseToken : null;
    const slotID = typeof data.processingSlotID === "string" ? data.processingSlotID : null;
    const attempt = Number(data.processingAttempt) || 0;
    const deadline = millis(data.processingDeadlineAt) ?? 0;
    const retry = attempt < CHAT_MEDIA_AUTOMATIC_ATTEMPTS && deadline > input.nowMillis;
    const slotRef = slotID ?
      input.firestore.collection("chatMediaProcessingSlots").doc(slotID) : null;
    const ownsSlot = slotRef ? await slotIsOwned(transaction, slotRef, leaseToken) : false;
    const principalRef = retry ? null : await principalSlotIfOwned(
      transaction, input.firestore, data.principalSlotID, input.uploadRef.path
    );
    if (slotRef && ownsSlot) releaseSlot(transaction, slotRef);
    if (retry) {
      transaction.update(input.uploadRef, {
        processingStatus: "queued",
        dispatchGeneration: FieldValue.increment(1),
        leaseToken: null,
        leaseExpiresAt: null,
        processingSlotID: null,
        executionName: null,
        retryable: true,
        failureCode: "execution_lease_expired",
        nextAttemptAt: Timestamp.fromMillis(input.nowMillis),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {changed: true, terminal: false, quarantinePaths: [], reason: "retry_queued"};
    }
    if (principalRef) releasePrincipalSlot(transaction, principalRef);
    transaction.update(input.uploadRef, terminalFields(
      "failed", "attempts_exhausted", input.nowMillis
    ));
    return terminalResult(data, "attempts_exhausted");
  });
}

function terminalFields(
  status: "failed" | "expired",
  failureCode: string,
  nowMillis: number
): Record<string, unknown> {
  return {
    processingStatus: status,
    retryable: false,
    failureCode,
    leaseToken: null,
    leaseExpiresAt: null,
    processingSlotID: null,
    executionName: null,
    nextAttemptAt: null,
    cleanupStatus: "pending",
    terminalAt: Timestamp.fromMillis(nowMillis),
    expiresAt: Timestamp.fromMillis(
      nowMillis + CHAT_MEDIA_TERMINAL_RETENTION_MILLIS
    ),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function terminalResult(
  data: FirebaseFirestore.DocumentData,
  reason: string
): ReconcileResult {
  return {
    changed: true,
    terminal: true,
    quarantinePaths: mediaCleanupPaths(data),
    reason,
  };
}

function mediaCleanupPaths(data: FirebaseFirestore.DocumentData): string[] {
  return [...new Set(stringArray(data.quarantinePaths))];
}
