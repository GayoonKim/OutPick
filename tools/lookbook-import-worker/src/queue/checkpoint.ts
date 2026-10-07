/* eslint-disable require-jsdoc, max-len */
import {type Firestore} from "firebase-admin/firestore";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";
import {readFailureRecord, writeFailureRecord} from "./failure-record.js";

type QueueItem = Record<string, unknown>;
type ItemAttemptOutcome = "succeeded" | "partialFailed" | "failed" |
  "awaitingReview" | "correctionRequired" | "retryWaiting" | "cancelled" |
  "recoveryRequired";

function itemExecution(db: Firestore, batch: Record<string, unknown>, item: QueueItem) {
  const collection = batch.kind === "discoverSeasons" ?
    "seasonDiscoveryJobs" : "importJobs";
  return db.doc(`brands/${String(batch.brandID)}/${collection}/${String(item.jobID)}`)
    .collection("executions").doc(String(item.executionID));
}

function validOrdinal(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_QUEUE_ITEM");
}

function progressKey(ordinal: number): string {
  return `item-${String(ordinal).padStart(4, "0")}`;
}

// 시도 횟수와 실행권을 같은 transaction에서 묶는다. 정상 분할은 다시 호출하지 않는다.
export async function beginBatchItemAttempt(
  db: Firestore, token: BatchOwnership,
  input: {ordinal: number; jobID: string; executionID: string}, now = Date.now(),
) {
  validOrdinal(input.ordinal);
  if (!input.jobID || !input.executionID || !Number.isSafeInteger(now) || now < 0) {
    throw new Error("INVALID_QUEUE_ITEM");
  }
  const batchRef = db.doc(`lookbookImportBatches/${token.batchID}`);
  return db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, token);
    if (batch.state !== "active") throw new Error("QUEUE_BATCH_DRAINING");
    const items = batch.items as QueueItem[];
    const item = items[input.ordinal];
    if (!item || item.admissionStatus !== "created" ||
        item.jobID !== input.jobID || item.executionID !== input.executionID) {
      throw new Error("QUEUE_ITEM_MISMATCH");
    }
    const executionRef = itemExecution(db, batch, item);
    const continuationRef = executionRef.collection("continuations").doc(token.batchID);
    const execution = (await transaction.get(executionRef)).data();
    const continuation = (await transaction.get(continuationRef)).data();
    if (!execution) throw new Error("QUEUE_EXECUTION_NOT_FOUND");
    if (execution.activeRunID === token.runID) {
      return {started: false as const, reason: "alreadyActive" as const};
    }
    const mode = typeof continuation?.mode === "string" ? continuation.mode :
      typeof execution.mode === "string" ? execution.mode : null;
    const restarting = execution.restartFromParsing === true;
    const approval = mode === "reviewApproval" && !restarting;
    if (approval && continuation?.status !== "queued") {
      return {started: false as const, reason: "notQueued" as const};
    }
    if (!approval && !["queued", "retryWaiting"].includes(String(execution.status))) {
      return {started: false as const, reason: "notQueued" as const};
    }
    if (execution.status === "retryWaiting" &&
        (typeof execution.retryAt !== "number" || execution.retryAt > now)) {
      return {started: false as const, reason: "retryNotDue" as const};
    }
    const attemptCount = Number(execution.attemptCount ?? 0);
    const attemptLimit = Number(execution.attemptLimit);
    if (!Number.isSafeInteger(attemptCount) || attemptCount < 0 ||
        !Number.isSafeInteger(attemptLimit) || attemptLimit < 1) {
      throw new Error("QUEUE_EXECUTION_CORRUPT");
    }
    const failureRecord = await readFailureRecord(db, transaction, batch, item, execution);
    if (!approval && attemptCount >= attemptLimit) {
      const updated = items.slice();
      updated[input.ordinal] = {...item, processingStatus: "failed",
        errorCode: "ATTEMPTS_EXHAUSTED", updatedAt: now};
      transaction.update(executionRef, {status: "failed", activeRunID: null,
        terminalReason: "ATTEMPTS_EXHAUSTED", updatedAt: now});
      if (continuation) {
        transaction.update(continuationRef, {
          status: "failed", terminalReason: "ATTEMPTS_EXHAUSTED", updatedAt: now,
        });
      }
      writeFailureRecord(transaction, failureRecord, {...batch, batchID: token.batchID},
        item, "failed", attemptCount, attemptLimit, now, "ATTEMPTS_EXHAUSTED");
      transaction.update(batchRef, {items: updated,
        stateRevision: Number(batch.stateRevision) + 1, updatedAt: now});
      transaction.set(batchRef.collection("progress").doc(progressKey(input.ordinal)), {
        value: JSON.stringify([item.itemID, "failed", "ATTEMPTS_EXHAUSTED"]),
        epoch: token.epoch, runID: token.runID,
      });
      return {started: false as const, reason: "attemptsExhausted" as const};
    }
    const nextAttempt = approval ? attemptCount : attemptCount + 1;
    const attemptID = String(nextAttempt).padStart(5, "0");
    const attemptRef = executionRef.collection("attempts").doc(attemptID);
    const attempt = await transaction.get(attemptRef);
    if (!approval && attempt.exists) throw new Error("QUEUE_ATTEMPT_CONFLICT");
    const updated = items.slice();
    updated[input.ordinal] = {...item, processingStatus: "active",
      activeRunID: token.runID, attemptCount: nextAttempt, updatedAt: now};
    transaction.update(executionRef, {status: "active", attemptCount: nextAttempt,
      restartFromParsing: false,
      activeRunID: token.runID, activeAttemptID: approval ? null : attemptID,
      startedAt: execution.startedAt ?? now, lastAttemptAt: approval ?
        execution.lastAttemptAt ?? null : now, updatedAt: now, retryAt: null});
    if (continuation) {
      transaction.update(continuationRef, {
        status: "active", startedRunID: token.runID, startedAt: now,
        updatedAt: now,
      });
    }
    if (!approval) {
      transaction.create(attemptRef, {
        attempt: nextAttempt, batchID: token.batchID,
        status: "active", runID: token.runID,
        epoch: token.epoch, startedAt: now,
      });
    }
    writeFailureRecord(transaction, failureRecord, {...batch, batchID: token.batchID}, item, "active",
      nextAttempt, attemptLimit, now);
    transaction.update(batchRef, {items: updated,
      stateRevision: Number(batch.stateRevision) + 1, updatedAt: now});
    transaction.set(batchRef.collection("progress").doc(progressKey(input.ordinal)), {
      value: JSON.stringify([item.itemID, "active", nextAttempt]),
      epoch: token.epoch, runID: token.runID,
    });
    const executionInput = continuation?.input ?? execution.input ?? null;
    return {started: true as const, attempt: nextAttempt, attemptID,
      attemptLimit, mode, approval, batchKind: String(batch.kind),
      input: executionInput && typeof executionInput === "object" &&
        !Array.isArray(executionInput) ?
        {...executionInput as Record<string, unknown>,
          ...(restarting ? {restartFromParsing: true} : {})} :
        restarting ? {restartFromParsing: true} : null};
  });
}

// 결과 checkpoint도 현재 epoch와 원자적으로 저장하고, stale run이면 전부 거절한다.
export async function finishBatchItemAttempt(
  db: Firestore, token: BatchOwnership,
  input: {ordinal: number; jobID: string; executionID: string;
    outcome: ItemAttemptOutcome; retryAt?: number; errorCode?: string}, now = Date.now(),
) {
  validOrdinal(input.ordinal);
  if (!Number.isSafeInteger(now) || now < 0 ||
      (input.outcome === "retryWaiting" &&
        (!Number.isSafeInteger(input.retryAt) || Number(input.retryAt) < now))) {
    throw new Error("INVALID_QUEUE_ITEM_RESULT");
  }
  if (input.errorCode !== undefined && input.errorCode.length > 128) {
    throw new Error("INVALID_QUEUE_ITEM_RESULT");
  }
  const batchRef = db.doc(`lookbookImportBatches/${token.batchID}`);
  return db.runTransaction(async (transaction) => {
    const batch = await readOwnedBatch(db, transaction, token);
    const items = batch.items as QueueItem[];
    const item = items[input.ordinal];
    if (!item || item.admissionStatus !== "created" ||
        item.jobID !== input.jobID || item.executionID !== input.executionID) {
      throw new Error("QUEUE_ITEM_MISMATCH");
    }
    const executionRef = itemExecution(db, batch, item);
    const continuationRef = executionRef.collection("continuations").doc(token.batchID);
    const execution = (await transaction.get(executionRef)).data();
    const continuation = (await transaction.get(continuationRef)).data();
    if (!execution || execution.activeRunID !== token.runID) {
      throw new Error("QUEUE_ITEM_RUN_LOST");
    }
    const activeAttemptID = typeof execution.activeAttemptID === "string" ?
      execution.activeAttemptID : null;
    const candidateID = activeAttemptID ?? (continuation?.mode === "reviewApproval" &&
      Number(execution.attemptCount) > 0 ? String(execution.attemptCount).padStart(5, "0") : null);
    const candidateRef = candidateID ? executionRef.collection("attempts").doc(candidateID) : null;
    const attempt = candidateRef ? (await transaction.get(candidateRef)).data() : undefined;
    if (activeAttemptID && !attempt) throw new Error("QUEUE_ATTEMPT_CORRUPT");
    const attemptRef = attempt ? candidateRef : null;
    const failureRecord = await readFailureRecord(db, transaction, batch, item, execution);
    const updated = items.slice();
    updated[input.ordinal] = {...item, processingStatus: input.outcome,
      activeRunID: null, retryAt: input.outcome === "retryWaiting" ? input.retryAt : null,
      errorCode: input.errorCode ?? null, updatedAt: now};
    const executionPatch: Record<string, unknown> = {
      status: input.outcome, activeRunID: null, activeAttemptID: null,
      updatedAt: now,
    };
    if (input.outcome === "retryWaiting") executionPatch.retryAt = input.retryAt;
    else if (input.outcome !== "recoveryRequired") executionPatch.finishedAt = now;
    if (input.errorCode) executionPatch.errorCode = input.errorCode;
    transaction.update(executionRef, executionPatch);
    if (attemptRef) {
      transaction.update(attemptRef, {
        status: input.outcome, endedAt: now,
        ...(input.errorCode ? {errorCode: input.errorCode} : {}),
      });
    }
    if (continuation) {
      transaction.update(continuationRef, {
        status: input.outcome, updatedAt: now,
        ...(input.outcome === "retryWaiting" ? {retryAt: input.retryAt} :
          input.outcome === "recoveryRequired" ? {} : {finishedAt: now}),
        ...(input.errorCode ? {errorCode: input.errorCode} : {}),
      });
    }
    writeFailureRecord(transaction, failureRecord, {...batch, batchID: token.batchID}, item, input.outcome,
      Number(execution.attemptCount ?? 0), Number(execution.attemptLimit), now, input.errorCode);
    transaction.update(batchRef, {items: updated,
      stateRevision: Number(batch.stateRevision) + 1, updatedAt: now});
    transaction.set(batchRef.collection("progress").doc(progressKey(input.ordinal)), {
      value: JSON.stringify([item.itemID, input.outcome,
        Number(execution.attemptCount ?? 0), input.errorCode ?? null]),
      epoch: token.epoch, runID: token.runID,
    });
    return {outcome: input.outcome, attempt: Number(execution.attemptCount ?? 0)};
  });
}
