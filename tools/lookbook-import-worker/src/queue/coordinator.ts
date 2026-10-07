/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import type {Firestore, Transaction} from "firebase-admin/firestore";
import {QUEUE_CONTRACT_VERSION, QUEUE_POLICY} from "./contracts.js";

const QUEUE = "lookbookImportQueue/main";
const BATCHES = "lookbookImportBatches";
export const QUEUE_TERMINAL_EXECUTION_STATUSES = [
  "succeeded", "partialFailed", "awaitingReview", "correctionRequired",
  "failed", "cancelled", "completed",
] as const;
export interface BatchDelivery {
  batchID: string;
  dispatchGeneration: number;
  queueContractVersion: number;
}
export interface BatchOwnership {
  batchID: string;
  owner: string;
  bootID: string;
  epoch: number;
  runID: string;
}
export type BatchRunContext = {projectID: string; revision: string;
  traceID: string | null};
type Document = Record<string, unknown>;

export function isQueueExecutionTerminal(status: unknown): boolean {
  return typeof status === "string" &&
    QUEUE_TERMINAL_EXECUTION_STATUSES.includes(
      status as typeof QUEUE_TERMINAL_EXECUTION_STATUSES[number],
    );
}

function identifier(value: unknown): asserts value is string {
  if (typeof value !== "string" || !value || value.length > 128 ||
      value === "." || value === ".." || value.includes("/") ||
      [...value].some((character) => character.charCodeAt(0) < 32)) {
    throw new Error("INVALID_QUEUE_CONTRACT");
  }
}
function millis(value: number) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_QUEUE_TIME");
}
export function parseBatchDelivery(value: unknown): BatchDelivery {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("INVALID_QUEUE_CONTRACT");
  const input = value as Document;
  if (Object.keys(input).some((key) => !["batchID", "dispatchGeneration", "queueContractVersion"].includes(key)) ||
      typeof input.batchID !== "string" || !/^[a-f0-9]{64}$/.test(input.batchID) ||
      !Number.isSafeInteger(input.dispatchGeneration) || Number(input.dispatchGeneration) < 0 ||
      input.queueContractVersion !== QUEUE_CONTRACT_VERSION) throw new Error("INVALID_QUEUE_CONTRACT");
  return {batchID: input.batchID, dispatchGeneration: Number(input.dispatchGeneration),
    queueContractVersion: QUEUE_CONTRACT_VERSION};
}

export async function claimBatch(
  db: Firestore, delivery: BatchDelivery, owner: string, bootID: string,
  now = Date.now(), allowedKinds?: readonly string[],
  context?: BatchRunContext,
): Promise<BatchOwnership | null> {
  const request = parseBatchDelivery(delivery);
  identifier(owner); identifier(bootID); millis(now);
  const queueRef = db.doc(QUEUE);
  const batchRef = db.doc(`${BATCHES}/${request.batchID}`);
  const ownership = await db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(queueRef)).data();
    const batch = (await transaction.get(batchRef)).data();
    if (!queue || !batch || queue.headBatchID !== request.batchID ||
        queue.state !== "idle" || queue.owner != null ||
        batch.contractVersion !== QUEUE_CONTRACT_VERSION ||
        batch.dispatchGeneration !== request.dispatchGeneration ||
        !["queued", "retryWaiting"].includes(batch.state) ||
        batch.preparationOwner != null || batch.owner != null) return null;
    if (allowedKinds && !allowedKinds.includes(String(batch.kind))) return null;
    if (batch.state === "retryWaiting" &&
        (typeof batch.retryAt !== "number" || batch.retryAt > now)) return null;
    if (!Array.isArray(batch.items) || batch.items.some((item: Document) => item.admissionStatus === "pending")) {
      throw new Error("QUEUE_NOT_PREPARED");
    }
    const epoch = Number(queue.epoch ?? 0) + 1;
    if (!Number.isSafeInteger(epoch) || epoch < 1) throw new Error("QUEUE_CORRUPT");
    const runID = `${request.batchID}-${epoch}`;
    const token = {batchID: request.batchID, owner, bootID, epoch, runID};
    transaction.update(queueRef, {state: "active", owner, bootID, epoch, runID, heartbeatAt: now});
    transaction.update(batchRef, {state: "active", owner, bootID, epoch, runID,
      progressFingerprint: batch.progressFingerprint ?? progressFingerprint({}),
      stateRevision: Number(batch.stateRevision) + 1, updatedAt: now});
    transaction.create(batchRef.collection("runs").doc(runID), {
      ...token, startedAt: now, heartbeatAt: now, state: "active", terminalConfirmed: false,
      dispatchGeneration: request.dispatchGeneration,
      ...(context ? {projectID: context.projectID, revision: context.revision,
        traceID: context.traceID} : {}),
    });
    return token;
  });
  if (ownership && context) {
    console.info(JSON.stringify({event: "lookbook_queue_run_claimed",
      batchID: request.batchID, epoch: ownership.epoch,
      runID: ownership.runID, bootID,
      projectID: context.projectID, revision: context.revision,
      traceID: context.traceID,
      ...(context.traceID ? {"logging.googleapis.com/trace":
        `projects/${context.projectID}/traces/${context.traceID}`} : {}),
    }));
  }
  return ownership;
}

// 이후 checkpoint/이미지 공개 transaction은 이 읽기를 먼저 수행한다.
// 실제 쓰기와 같은 transaction을 사용하고 별도 update로 분리하지 않는다.
export async function readOwnedBatch(db: Firestore, transaction: Transaction, token: BatchOwnership) {
  identifier(token.batchID); identifier(token.owner); identifier(token.bootID); identifier(token.runID);
  const queue = (await transaction.get(db.doc(QUEUE))).data();
  const batch = (await transaction.get(db.doc(`${BATCHES}/${token.batchID}`))).data();
  if (!queue || !batch || queue.headBatchID !== token.batchID ||
      queue.owner !== token.owner || queue.bootID !== token.bootID ||
      queue.epoch !== token.epoch || queue.runID !== token.runID ||
      batch.owner !== token.owner || batch.epoch !== token.epoch ||
      batch.runID !== token.runID || !["active", "draining"].includes(batch.state) ||
      !["active", "draining"].includes(queue.state)) {
    throw new Error("QUEUE_OWNERSHIP_LOST");
  }
  return batch;
}

export async function heartbeatBatch(db: Firestore, token: BatchOwnership, now = Date.now()) {
  millis(now);
  return db.runTransaction(async (transaction) => {
    await readOwnedBatch(db, transaction, token);
    transaction.update(db.doc(QUEUE), {heartbeatAt: now});
    transaction.update(db.doc(`${BATCHES}/${token.batchID}/runs/${token.runID}`), {heartbeatAt: now});
  });
}

export async function beginBatchDrain(db: Firestore, token: BatchOwnership, now = Date.now()) {
  millis(now);
  return db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, token);
    transaction.update(db.doc(QUEUE), {state: "draining"});
    transaction.update(db.doc(`${BATCHES}/${token.batchID}`), {state: "draining",
      stateRevision: Number(batch.stateRevision) + 1, updatedAt: now});
    transaction.update(db.doc(`${BATCHES}/${token.batchID}/runs/${token.runID}`), {state: "draining"});
  });
}

export function progressFingerprint(progress: Record<string, string>): string {
  const entries = Object.entries(progress).sort(([left], [right]) => left.localeCompare(right));
  if (entries.some(([key, value]) => !key || typeof value !== "string" || !value)) {
    throw new Error("INVALID_QUEUE_PROGRESS");
  }
  return createHash("sha256").update(JSON.stringify(entries)).digest("hex");
}

// phase 전환/공개 이미지 집합처럼 실제로 저장한 진행만 기록한다.
// heartbeat/시간 경과는 이 경로를 사용하지 않는다.
export async function writeBatchProgress(
  db: Firestore, token: BatchOwnership, key: string, value: string,
) {
  identifier(key);
  if (!value || value.length > 4096) throw new Error("INVALID_QUEUE_PROGRESS");
  return db.runTransaction(async (transaction) => {
    await readOwnedBatch(db, transaction, token);
    transaction.set(db.doc(`${BATCHES}/${token.batchID}/progress/${key}`), {
      value, epoch: token.epoch, runID: token.runID,
    });
  });
}

export type BatchFinish = {
  disposition: "complete" | "continue" | "retry" | "recovery";
  drained: boolean;
  inFlight: number;
  retryAt?: number;
  reason?: string;
  resourceEvidence?: {
    startedAt: number;
    sampleCount: number;
    maxMemoryRatio: number | null;
    memorySource: string | null;
    memoryLimitBytes: number | null;
    memoryStop: string | null;
    admissionStop: string | null;
    drainTargetExceeded: boolean;
  };
};

export async function finishBatchRun(
  db: Firestore, token: BatchOwnership, result: BatchFinish, now = Date.now(),
) {
  millis(now);
  if (typeof result.drained !== "boolean" || !Number.isInteger(result.inFlight) || result.inFlight < 0 ||
      !["complete", "continue", "retry", "recovery"].includes(result.disposition)) {
    throw new Error("INVALID_QUEUE_COMPLETION");
  }
  if (result.disposition === "retry" &&
      (typeof result.retryAt !== "number" || !Number.isSafeInteger(result.retryAt) || result.retryAt < now)) {
    throw new Error("INVALID_QUEUE_RETRY_TIME");
  }
  const batchRef = db.doc(`${BATCHES}/${token.batchID}`);
  return db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, token);
    if (batch.state !== "draining") throw new Error("QUEUE_NOT_DRAINING");
    const progress = await transaction.get(batchRef.collection("progress"));
    const fingerprint = progressFingerprint(Object.fromEntries(
      progress.docs.map((document) => [document.id, document.data().value]),
    ));
    const drained = result.drained && result.inFlight === 0;
    const changed = batch.progressFingerprint !== fingerprint;
    const noProgressSegments = changed ? 0 : Number(batch.noProgressSegments ?? 0) +
      (result.disposition === "continue" ? 1 : 0);
    const recovery = !drained || result.disposition === "recovery" ||
      noProgressSegments >= QUEUE_POLICY.noProgressSegments;
    const state = recovery ? "recoveryRequired" : result.disposition === "complete" ? "released" :
      result.disposition === "retry" ? "retryWaiting" : "queued";
    if (result.disposition === "complete" && !recovery) {
      const items = batch.items as Document[];
      for (const item of items.filter((value) => value.admissionStatus === "created")) {
        identifier(item.jobID); identifier(item.executionID);
        const collection = batch.kind === "discoverSeasons" ? "seasonDiscoveryJobs" : "importJobs";
        const executionRef = db.doc(`brands/${batch.brandID}/${collection}/${item.jobID}/executions/${item.executionID}`);
        const execution = (await transaction.get(executionRef)).data();
        const continuation = (await transaction.get(executionRef.collection("continuations").doc(token.batchID))).data();
        if (!isQueueExecutionTerminal(execution?.status) ||
            (continuation && !isQueueExecutionTerminal(continuation.status))) {
          throw new Error("QUEUE_EXECUTION_NOT_TERMINAL");
        }
      }
    }
    const generation = Number(batch.dispatchGeneration) + (state === "queued" || state === "retryWaiting" ? 1 : 0);
    transaction.update(batchRef, {state, owner: recovery ? token.owner : null,
      stateRevision: Number(batch.stateRevision) + 1, updatedAt: now,
      dispatchGeneration: generation, dispatchState: state === "queued" || state === "retryWaiting" ? "pending" : "none",
      ...(state === "released" ? {releasedAt: now,
        detailCleanupAfter: now + QUEUE_POLICY.successDetailRetentionMs,
        receiptExpiresAt: now + QUEUE_POLICY.receiptRetentionMs,
        retentionNextAt: now + QUEUE_POLICY.successDetailRetentionMs} : {}),
      retryAt: state === "retryWaiting" ? result.retryAt : null,
      progressFingerprint: fingerprint, noProgressSegments,
      recoveryReason: recovery ? result.reason ?? (drained ? "NO_PROGRESS" : "DRAIN_UNCONFIRMED") : null});
    transaction.update(db.doc(QUEUE), {state: recovery ? "recoveryRequired" : "idle",
      owner: recovery ? token.owner : null, heartbeatAt: now});
    transaction.update(batchRef.collection("runs").doc(token.runID), {
      state, finishedAt: now, terminalConfirmed: drained, inFlight: result.inFlight,
      progressFingerprint: fingerprint, disposition: result.disposition,
      ...(result.resourceEvidence ? {resourceEvidence: result.resourceEvidence} : {}),
    });
    return state;
  });
}

// 준비 실패/전부 중복인 batch도 순번을 건너뛰지 않고 release를 확인한다.
export async function advanceReleasedHead(db: Firestore) {
  const queueRef = db.doc(QUEUE);
  return db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(queueRef)).data();
    if (!queue || queue.state === "recoveryRequired" || queue.owner != null || !queue.headBatchID) return null;
    const headRef = db.doc(`${BATCHES}/${queue.headBatchID}`);
    const head = (await transaction.get(headRef)).data();
    if (!head || head.state !== "released" || head.preparationOwner != null) return null;
    if (head.runID) {
      const run = (await transaction.get(headRef.collection("runs").doc(head.runID))).data();
      if (run?.terminalConfirmed !== true) throw new Error("QUEUE_DRAIN_UNCONFIRMED");
    }
    const next = await transaction.get(db.collection(BATCHES).where("sequence", "==", Number(head.sequence) + 1).limit(2));
    if (next.size > 1) throw new Error("QUEUE_CORRUPT");
    if (next.empty && Number(queue.nextSequence) > Number(head.sequence) + 1) throw new Error("QUEUE_SEQUENCE_GAP");
    const nextID = next.docs[0]?.id ?? null;
    transaction.update(queueRef, {headBatchID: nextID, state: "idle"});
    return nextID;
  });
}
