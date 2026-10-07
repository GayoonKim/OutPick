/* eslint-disable require-jsdoc */
import type {Firestore, Transaction} from "firebase-admin/firestore";
import {
  parseQueueRequestEnvelope, newQueueAdmissionTimeError, QUEUE_POLICY,
} from "./contracts.js";
import {
  BATCH_COLLECTION, QUEUE_PATH, canonicalJSON, queueBatchID,
  queueHash, queueDocumentID,
  type AdmissionRequest, type AdmissionTarget, type QueueBatch,
} from "./model.js";
import {projectQueueReceipt} from "./projection.js";

export type QueueAuthorization = (
  transaction: Transaction, uid: string, brandID: string
) => Promise<void>;
export type QueueAdmissionHooks = {
  authorize: QueueAuthorization;
  freezeTargets: (transaction: Transaction) => Promise<AdmissionTarget[]>;
  // snapshot 읽기는 freezeTargets에서 끝내고 부수 기록만 원자적으로 쓴다.
  commit?: (transaction: Transaction, batch: QueueBatch) => void;
};

export async function admitQueueRequest(
  db: Firestore, uid: string, input: AdmissionRequest,
  hooks: QueueAdmissionHooks, now = Date.now()
) {
  return db.runTransaction((transaction) =>
    admitQueueRequestInTransaction(db, transaction, uid, input, hooks, now));
}

// 브랜드 생성처럼 다른 원자적 변경에 접수를 포함할 때 사용한다.
// freezeTargets까지 모든 읽기를 끝낸 뒤 큐 기록을 쓴다.
export async function admitQueueRequestInTransaction(
  db: Firestore, transaction: Transaction, uid: string, input: AdmissionRequest,
  hooks: QueueAdmissionHooks, now = Date.now()
) {
  if (!uid) throw new Error("PERMISSION_DENIED");
  const envelope = parseQueueRequestEnvelope(input);
  const brandID = queueDocumentID(input.brandID);
  const kinds = ["importSeasons", "discoverSeasons", "reviewApproval",
    "manualRetry", "assetRetry", "repair"];
  if (!kinds.includes(input.kind)) throw new Error("INVALID_CONTRACT");
  const payloadDigest = queueHash({
    ...envelope, brandID, kind: input.kind, payload: input.payload,
  });
  const batchID = queueBatchID(uid, envelope.requestID);
  const batchRef = db.collection(BATCH_COLLECTION).doc(batchID);
  const queueRef = db.doc(QUEUE_PATH);
  await hooks.authorize(transaction, uid, brandID);
  const existing = await transaction.get(batchRef);
  if (existing.exists) {
    const batch = existing.data() as QueueBatch;
    if (batch.requestedBy !== uid || batch.payloadDigest !== payloadDigest) {
      throw new Error("REQUEST_ID_CONFLICT");
    }
    return projectQueueReceipt(batchID, batch);
  }
  const timeError = newQueueAdmissionTimeError(
    envelope.requestCreatedAt, now);
  if (timeError) throw new Error(timeError);
  // 현재 snapshot 검사는 기존 영수증 확인 이후 같은 transaction에서 한다.
  const targets = await hooks.freezeTargets(transaction);
  if (targets.length < 1 ||
      targets.length > QUEUE_POLICY.maxSelectedSeasons ||
      (input.kind === "discoverSeasons" && targets.length !== 1)) {
    throw new Error("INVALID_CONTRACT");
  }
  const targetIDs = new Set<string>();
  for (const target of targets) {
    queueDocumentID(target.targetID);
    if (target.existingJobID !== undefined) {
      queueDocumentID(target.existingJobID);
    }
    if (target.existingExecutionID !== undefined) {
      queueDocumentID(target.existingExecutionID);
      if (!target.existingJobID) throw new Error("INVALID_CONTRACT");
    }
    if (target.assetRetry !== undefined) {
      queueDocumentID(target.assetRetry.jobID);
      if (target.existingJobID !== undefined ||
          target.collection !== "importJobs" ||
          !["importSeasons", "assetRetry"].includes(input.kind)) {
        throw new Error("INVALID_CONTRACT");
      }
    }
    if (targetIDs.has(target.targetID) || !target.claimKey ||
        target.collection !== (input.kind === "discoverSeasons" ?
          "seasonDiscoveryJobs" : "importJobs")) {
      throw new Error("INVALID_CONTRACT");
    }
    targetIDs.add(target.targetID);
  }
  // 원본/HTML 대신 서버 adapter의 최소 JSON 입력만 고정한다.
  canonicalJSON(targets);
  const queue = (await transaction.get(queueRef)).data();
  const sequence = queue?.nextSequence ?? 1;
  if (!Number.isSafeInteger(sequence) || sequence < 1 ||
      sequence >= Number.MAX_SAFE_INTEGER) throw new Error("QUEUE_CORRUPT");
  const batch: QueueBatch = {
    contractVersion: 1, requestID: envelope.requestID,
    requestCreatedAt: envelope.requestCreatedAt, requestedBy: uid, brandID,
    kind: input.kind, payloadDigest, sequence,
    state: "preparing", stateRevision: 1,
    items: targets.map((target, ordinal) => ({
      itemID: queueHash([batchID, ordinal]), targetID: target.targetID,
      ordinal, admissionStatus: target.errorCode ? "failed" : "pending",
      jobID: null, executionID: null, errorCode: target.errorCode ?? null,
    })),
    preparationAttempts: 0, preparationOwner: null,
    dispatchGeneration: 0, dispatchState: "none",
    createdAt: now, updatedAt: now,
  };
  transaction.create(batchRef, batch);
  targets.forEach((target, ordinal) => {
    transaction.create(batchRef.collection("inputs").doc(String(ordinal)),
      target);
  });
  transaction.set(queueRef, {
    nextSequence: sequence + 1,
    preparationSequence: queue?.preparationSequence ?? 1,
    headBatchID: queue?.headBatchID ?? batchID,
    state: queue?.state ?? "idle",
  }, {merge: true});
  hooks.commit?.(transaction, batch);
  return projectQueueReceipt(batchID, batch);
}

export async function getQueueReceipt(
  db: Firestore, uid: string, requestID: string,
  authorize: QueueAuthorization
) {
  const batchID = queueBatchID(uid, requestID);
  return getQueueReceiptByBatchID(db, uid, batchID, authorize);
}

export async function getQueueReceiptByBatchID(
  db: Firestore, uid: string, batchID: string, authorize: QueueAuthorization
) {
  queueDocumentID(batchID);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(
      db.doc(`${BATCH_COLLECTION}/${batchID}`));
    if (!snapshot.exists) throw new Error("REQUEST_NOT_FOUND");
    const batch = snapshot.data() as QueueBatch;
    if (batch.requestedBy !== uid) throw new Error("PERMISSION_DENIED");
    await authorize(transaction, uid, batch.brandID);
    return projectQueueReceipt(batchID, batch);
  });
}
