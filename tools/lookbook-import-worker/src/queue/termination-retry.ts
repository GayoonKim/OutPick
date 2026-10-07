/* eslint-disable require-jsdoc, max-len */
import type {Firestore} from "firebase-admin/firestore";
import {parseBatchDelivery, type BatchDelivery} from "./coordinator.js";
import type {RecoveryEvidenceProvider} from "./recovery.js";
import {RetryableImportError} from "../import-error.js";
import {QUEUE_POLICY} from "./contracts.js";

// Cloud Tasks 재전달은 종료 증거를 확인한 뒤 같은 차례에서 새 추출을 시작한다.
// 이전 실행의 중간 이미지/승인 상태를 복원하지 않는다.
export async function settleTerminatedSeasonRun(input: {
  firestore: Firestore; delivery: unknown; projectID: string; serviceName: string;
  evidenceProvider: RecoveryEvidenceProvider; now?: number;
}): Promise<BatchDelivery> {
  const delivery = parseBatchDelivery(input.delivery);
  const db = input.firestore;
  const queueRef = db.doc("lookbookImportQueue/main");
  const batchRef = db.doc(`lookbookImportBatches/${delivery.batchID}`);
  const [queueSnapshot, batchSnapshot] = await Promise.all([queueRef.get(), batchRef.get()]);
  const queue = queueSnapshot.data();
  const batch = batchSnapshot.data();
  if (!queue || !batch || queue.headBatchID !== delivery.batchID ||
      !["active", "draining", "recoveryRequired"].includes(String(batch.state))) return delivery;
  if (batch.dispatchGeneration !== delivery.dispatchGeneration) return delivery;
  if (!["importSeasons", "manualRetry", "reviewApproval"].includes(String(batch.kind))) {
    throw new RetryableImportError("QUEUE_TERMINATION_REQUIRES_REVIEW");
  }
  const runRef = batchRef.collection("runs").doc(String(batch.runID));
  const run = (await runRef.get()).data();
  if (!run || run.projectID !== input.projectID || typeof run.revision !== "string" ||
      typeof run.traceID !== "string" || typeof run.startedAt !== "number" ||
      run.epoch !== batch.epoch || queue.runID !== batch.runID || queue.epoch !== batch.epoch ||
      run.resourceEvidence?.memoryStop || run.resourceEvidence?.admissionStop) {
    throw new RetryableImportError("QUEUE_TERMINATION_UNCONFIRMED");
  }
  const proof = await input.evidenceProvider.findTerminatedInstance({projectID: input.projectID,
    serviceName: input.serviceName, revision: run.revision, traceID: run.traceID, startedAt: run.startedAt});
  if (!proof || proof.projectID !== input.projectID || proof.serviceName !== input.serviceName ||
      proof.revision !== run.revision || proof.traceID !== run.traceID ||
      !proof.instanceID || !proof.insertID || !Number.isFinite(Date.parse(proof.timestamp)) ||
      Date.parse(proof.timestamp) < run.startedAt) throw new RetryableImportError("QUEUE_TERMINATION_UNCONFIRMED");
  const now = input.now ?? Date.now();
  return db.runTransaction(async (tx) => {
    const [currentQueue, currentBatch, currentRun] = await Promise.all([
      tx.get(queueRef), tx.get(batchRef), tx.get(runRef),
    ]);
    const q = currentQueue.data(); const b = currentBatch.data(); const r = currentRun.data();
    if (!q || !b || !r || q.headBatchID !== delivery.batchID ||
        q.runID !== batch.runID || q.epoch !== batch.epoch || q.state !== queue.state ||
        b.runID !== batch.runID || b.stateRevision !== batch.stateRevision ||
        b.dispatchGeneration !== delivery.dispatchGeneration ||
        r.startedAt !== run.startedAt || r.traceID !== run.traceID || r.revision !== run.revision) {
      throw new RetryableImportError("QUEUE_TERMINATION_SOURCE_CHANGED");
    }
    const items = Array.isArray(b.items) ? b.items as Array<Record<string, unknown>> : [];
    if (items.length > QUEUE_POLICY.maxSelectedSeasons) throw new Error("QUEUE_BATCH_CORRUPT");
    const interrupted = items.filter((item) => item.admissionStatus === "created" &&
      ["active", "recoveryRequired", "retryWaiting"].includes(String(item.processingStatus)));
    const entries = await Promise.all(interrupted.map(async (item) => {
      const rootRef = db.doc(`brands/${String(b.brandID)}/importJobs/${String(item.jobID)}`);
      const executionRef = rootRef.collection("executions").doc(String(item.executionID));
      const [root, execution, continuation] = await Promise.all([tx.get(rootRef), tx.get(executionRef),
        tx.get(executionRef.collection("continuations").doc(delivery.batchID))]);
      const e = execution.data(); const j = root.data();
      if (!e || !j || j.jobType !== "importSeasonFromURL" ||
          j.queueExecutionID !== item.executionID || j.queueActiveRunID != null && j.queueActiveRunID !== b.runID ||
          e.activeRunID != null && e.activeRunID !== b.runID ||
          !["active", "recoveryRequired", "retryWaiting"].includes(String(e.status)) ||
          !Number.isSafeInteger(e.attemptCount) || e.attemptCount < 1 ||
          !Number.isSafeInteger(e.attemptLimit) || e.attemptLimit !== QUEUE_POLICY.importAttempts) {
        throw new Error("QUEUE_TERMINATION_EXECUTION_CHANGED");
      }
      const attemptID = typeof e.activeAttemptID === "string" ? e.activeAttemptID :
        String(e.attemptCount).padStart(5, "0");
      const attempt = await tx.get(executionRef.collection("attempts").doc(attemptID));
      return {item, rootRef, executionRef, continuation, attempt};
    }));
    const updated = items.map((item) => interrupted.includes(item) ? {...item,
      processingStatus: "retryWaiting", activeRunID: null, retryAt: now,
      errorCode: "WORKER_TERMINATED", updatedAt: now} : item);
    for (const entry of entries) {
      tx.update(entry.rootRef, {status: "queued", phase: "dispatching", resumeFrom: "parsing",
        queueActiveRunID: null, leaseOwner: null, leaseExpiresAt: null,
        lastFailureStage: "workerTermination", updatedAt: new Date(now)});
      tx.update(entry.executionRef, {status: "retryWaiting", retryAt: now,
        restartFromParsing: true, activeRunID: null, activeAttemptID: null,
        terminationRunID: b.runID, updatedAt: now});
      if (entry.attempt.exists) {
        tx.update(entry.attempt.ref, {status: "failed", endedAt: now,
          errorCode: "WORKER_TERMINATED", terminationRunID: b.runID});
      }
      if (entry.continuation.exists) tx.update(entry.continuation.ref, {status: "queued", updatedAt: now});
    }
    const generation = Number(b.dispatchGeneration) + 1;
    tx.update(runRef, {terminationEvidence: proof, terminationVerifiedAt: now,
      settlement: "restartFromParsing", settledAt: now});
    tx.set(db.doc(`lookbookImportRecoveryAudits/termination-${b.runID}`), {
      action: "automaticTerminationRetry", batchID: delivery.batchID, runID: b.runID,
      evidence: proof, interruptedItemCount: entries.length, createdAt: now,
      expiresAt: now + QUEUE_POLICY.recoveryAuditRetentionMs,
    });
    tx.update(batchRef, {state: "queued", owner: null, bootID: null, runID: null,
      items: updated, dispatchGeneration: generation, dispatchState: "pending",
      stateRevision: Number(b.stateRevision) + 1, recoveryReason: null, retryAt: null, updatedAt: now});
    tx.update(queueRef, {state: "idle", owner: null, bootID: null, runID: null,
      recoveryReason: null, heartbeatAt: now});
    return {...delivery, dispatchGeneration: generation};
  });
}
