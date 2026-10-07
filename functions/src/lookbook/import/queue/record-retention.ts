/* eslint-disable require-jsdoc, max-len */
import {FieldValue, type DocumentReference, type Firestore} from "firebase-admin/firestore";
import {randomUUID} from "node:crypto";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {QUEUE_POLICY} from "./contracts.js";
import {BATCH_COLLECTION, QUEUE_PATH, type QueueBatch} from "./model.js";

const LEASE_PATH = "lookbookImportMaintenance/recordCleanup";
const TERMINAL_EXECUTIONS = new Set([
  "succeeded", "partialFailed", "failed", "cancelled", "completed",
  "superseded",
]);
const FAILURE_ATTEMPTS = ["retryWaiting", "failed", "recoveryRequired"];
const LEASE_MS = 10 * 60 * 1000;

type LinkedState = {status: string; priorFailure: boolean};
export type BatchRetentionAction = "protect" | "deferFailure" |
  "pruneDetails" | "deleteReceipt" | "notDue";

export function decideBatchRetention(input: {
  batchState: unknown;
  releasedAt: unknown;
  detailCleanupAfter?: unknown;
  receiptExpiresAt?: unknown;
  detailsPruned?: unknown;
  linkedStates: readonly LinkedState[];
  admissionFailure: boolean;
  now: number;
}): BatchRetentionAction {
  if (input.batchState !== "released" ||
      !Number.isSafeInteger(input.releasedAt) ||
      !Number.isSafeInteger(input.now)) return "protect";
  if (input.linkedStates.some((item) => item.status === "awaitingReview" ||
      !TERMINAL_EXECUTIONS.has(item.status))) return "protect";
  const hasFailure = input.admissionFailure ||
    input.linkedStates.some((item) => item.status === "partialFailed" ||
      item.status === "failed" || item.status === "cancelled" ||
      item.priorFailure);
  const releasedAt = Number(input.releasedAt);
  const detailDue = releasedAt + (hasFailure ?
    QUEUE_POLICY.resolvedFailureRetentionMs :
    QUEUE_POLICY.successDetailRetentionMs);
  if (input.detailsPruned === true) {
    const receiptDue = Number.isSafeInteger(input.receiptExpiresAt) ?
      Number(input.receiptExpiresAt) :
      releasedAt + QUEUE_POLICY.receiptRetentionMs;
    return input.now >= receiptDue ? "deleteReceipt" : "notDue";
  }
  if (hasFailure && input.now < detailDue) return "deferFailure";
  if (input.now < detailDue) return "notDue";
  return "pruneDetails";
}

export type RetentionCounts = {
  scanned: number;
  changed: number;
  protected: number;
  failed: number;
  remaining: number;
};

async function claimLease(
  firestore: Firestore, path: string, owner: string, now: number,
) {
  const ref = firestore.doc(path);
  return firestore.runTransaction(async (transaction) => {
    const data = (await transaction.get(ref)).data();
    if (typeof data?.leaseUntil === "number" && data.leaseUntil > now) return false;
    transaction.set(ref, {owner, leaseUntil: now + LEASE_MS,
      startedAt: now, updatedAt: now}, {merge: true});
    return true;
  });
}

async function releaseLease(
  firestore: Firestore, path: string, owner: string, now: number,
) {
  const ref = firestore.doc(path);
  await firestore.runTransaction(async (transaction) => {
    const current = (await transaction.get(ref)).data();
    if (current?.owner !== owner) return;
    transaction.set(ref, {owner: null, leaseUntil: null,
      finishedAt: now, updatedAt: now}, {merge: true});
  });
}

async function linkedStates(
  firestore: Firestore, batchID: string, batch: QueueBatch,
): Promise<{states: LinkedState[]; unresolved: boolean}> {
  const collection = batch.kind === "discoverSeasons" ?
    "seasonDiscoveryJobs" : "importJobs";
  const result: LinkedState[] = [];
  for (const item of batch.items) {
    if (item.admissionStatus === "failed" || item.admissionStatus === "skipped") {
      continue;
    }
    if (!item.jobID) return {states: result, unresolved: true};
    const jobRef = firestore.doc(`brands/${batch.brandID}/${collection}/${item.jobID}`);
    const job = (await jobRef.get()).data();
    if (!job) return {states: result, unresolved: true};
    const executionID = item.executionID ??
      (typeof job.queueExecutionID === "string" ? job.queueExecutionID : null);
    if (!executionID) {
      const status = String(job.status ?? "unknown");
      result.push({status, priorFailure: status === "partialFailed" ||
        status === "failed"});
      if (status === "awaitingReview" || !TERMINAL_EXECUTIONS.has(status)) {
        return {states: result, unresolved: true};
      }
      continue;
    }
    const executionRef = jobRef.collection("executions").doc(executionID);
    const execution = (await executionRef.get()).data();
    if (!execution) return {states: result, unresolved: true};
    const continuation = (await executionRef.collection("continuations")
      .doc(batchID).get()).data();
    const status = String(continuation?.status ?? execution.status ?? "unknown");
    const failedAttempts = await executionRef.collection("attempts")
      .where("status", "in", FAILURE_ATTEMPTS).limit(1).get();
    result.push({status, priorFailure: !failedAttempts.empty});
    if (status === "awaitingReview" || !TERMINAL_EXECUTIONS.has(status)) {
      return {states: result, unresolved: true};
    }
  }
  return {states: result, unresolved: false};
}

type WorkBudget = {pages: number; writes: number; startedAt: number;
  now: () => number; maxPages?: number; maxWrites?: number};

function hasBudget(budget: WorkBudget): boolean {
  return budget.pages < (budget.maxPages ?? QUEUE_POLICY.cleanupMaxPages) &&
    hasWriteBudget(budget);
}

function hasWriteBudget(budget: WorkBudget): boolean {
  return budget.writes < (budget.maxWrites ?? QUEUE_POLICY.cleanupMaxOperations) &&
    budget.now() - budget.startedAt < QUEUE_POLICY.cleanupAdmissionMs;
}

async function deleteCollectionBounded(
  ref: FirebaseFirestore.Query,
  firestore: Firestore,
  budget: WorkBudget,
): Promise<boolean> {
  while (hasBudget(budget)) {
    const limit = Math.min(QUEUE_POLICY.cleanupPageSize,
      (budget.maxWrites ?? QUEUE_POLICY.cleanupMaxOperations) - budget.writes);
    if (limit <= 0) return false;
    const page = await ref.limit(limit).get();
    if (page.empty) return true;
    budget.pages++;
    const batch = firestore.batch();
    page.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    budget.writes += page.size;
    if (page.size < limit) return true;
  }
  const remainder = await ref.limit(1).get();
  return remainder.empty;
}

async function pruneBatchDetails(
  firestore: Firestore, ref: DocumentReference, budget: WorkBudget,
): Promise<boolean> {
  const collections: FirebaseFirestore.CollectionReference[] = [
    ref.collection("inputs"), ref.collection("progress"),
    ref.collection("preparationAttempts"), ref.collection("runs"),
  ];
  for (const collection of collections) {
    if (!hasBudget(budget)) return false;
    if (!await deleteCollectionBounded(collection, firestore, budget)) return false;
  }
  const attempts = firestore.collectionGroup("attempts")
    .where("batchID", "==", ref.id);
  if (!hasBudget(budget) ||
      !await deleteCollectionBounded(attempts, firestore, budget)) return false;
  return true;
}

async function deferBatch(
  ref: DocumentReference, now: number, budget: WorkBudget,
): Promise<void> {
  if (budget.writes >= (budget.maxWrites ?? QUEUE_POLICY.cleanupMaxOperations)) return;
  await ref.update({retentionNextAt: now + QUEUE_POLICY.recordCleanupIntervalMs,
    updatedAt: now});
  budget.writes++;
}

async function processBatchRetention(
  firestore: Firestore, document: FirebaseFirestore.QueryDocumentSnapshot,
  queue: FirebaseFirestore.DocumentData | undefined,
  budget: WorkBudget,
): Promise<void> {
  const batch = document.data() as QueueBatch;
  const now = budget.now();
  if (queue?.headBatchID === document.id || batch.state !== "released") {
    await deferBatch(document.ref, now, budget);
    return;
  }
  const linked = await linkedStates(firestore, document.id, batch);
  if (linked.unresolved) {
    await deferBatch(document.ref, now, budget);
    return;
  }
  const action = decideBatchRetention({
    batchState: batch.state, releasedAt: batch.releasedAt,
    detailCleanupAfter: batch.detailCleanupAfter,
    receiptExpiresAt: batch.receiptExpiresAt,
    detailsPruned: batch.detailsPruned,
    linkedStates: linked.states,
    admissionFailure: batch.items.some((item) => item.admissionStatus === "failed"),
    now,
  });
  if (action === "protect") {
    await deferBatch(document.ref, now, budget);
    return;
  }
  if (action === "deferFailure") {
    const releasedAt = Number(batch.releasedAt);
    await document.ref.update({
      detailCleanupAfter: releasedAt + QUEUE_POLICY.resolvedFailureRetentionMs,
      retentionNextAt: releasedAt + QUEUE_POLICY.resolvedFailureRetentionMs,
      updatedAt: now,
    });
    budget.writes++;
    return;
  }
  if (action === "notDue") {
    const nextAt = batch.detailsPruned === true ? batch.receiptExpiresAt :
      batch.detailCleanupAfter;
    if (typeof nextAt === "number" && nextAt > now) {
      await document.ref.update({retentionNextAt: nextAt});
      budget.writes++;
    } else {
      await deferBatch(document.ref, now, budget);
    }
    return;
  }
  if (action === "pruneDetails") {
    const complete = await pruneBatchDetails(firestore, document.ref, budget);
    if (!complete) {
      await deferBatch(document.ref, budget.now(), budget);
      return;
    }
    if (budget.writes >= (budget.maxWrites ?? QUEUE_POLICY.cleanupMaxOperations)) return;
    const receiptExpiresAt = Number.isSafeInteger(batch.receiptExpiresAt) ?
      Number(batch.receiptExpiresAt) :
      Number(batch.releasedAt) + QUEUE_POLICY.receiptRetentionMs;
    await document.ref.update({detailsPruned: true,
      detailCleanupAfter: FieldValue.delete(), retentionNextAt: receiptExpiresAt,
      receiptExpiresAt, updatedAt: budget.now()});
    budget.writes++;
    return;
  }
  if (action === "deleteReceipt") {
    if (budget.writes >= (budget.maxWrites ?? QUEUE_POLICY.cleanupMaxOperations)) return;
    await document.ref.delete();
    budget.writes++;
  }
}

async function cleanupBrandReceipts(
  firestore: Firestore,
  queue: FirebaseFirestore.DocumentData | undefined,
  budget: WorkBudget,
  counts: RetentionCounts,
): Promise<void> {
  const candidates = await firestore.collection("brandCreationRequests")
    .where("retentionNextAt", "<=", budget.now())
    .orderBy("retentionNextAt")
    .limit(QUEUE_POLICY.cleanupPageSize).get();
  if (candidates.empty) return;
  budget.pages++;
  for (const document of candidates.docs) {
    if (!hasWriteBudget(budget)) break;
    counts.scanned++;
    const data = document.data();
    const expiry = data.receiptExpiresAt;
    let deferUntil = budget.now() + QUEUE_POLICY.recordCleanupIntervalMs;
    if (Number.isSafeInteger(expiry) && Number(expiry) > budget.now()) {
      deferUntil = Number(expiry);
    }
    const batchID = typeof data.result?.batchID === "string" ?
      data.result.batchID : null;
    let protectedReceipt = false;
    try {
      if (batchID && queue?.headBatchID === batchID) {
        protectedReceipt = true;
      } else if (batchID) {
        const batchSnapshot = await firestore.collection(BATCH_COLLECTION)
          .doc(batchID).get();
        if (batchSnapshot.exists) {
          const batch = batchSnapshot.data() as QueueBatch;
          if (batch.state !== "released") {
            protectedReceipt = true;
          } else {
            const linked = await linkedStates(firestore, batchID, batch);
            protectedReceipt = linked.unresolved;
          }
        }
      }
      if (protectedReceipt || !Number.isSafeInteger(expiry) ||
          Number(expiry) > budget.now()) {
        if (budget.writes >= (budget.maxWrites ??
            QUEUE_POLICY.cleanupMaxOperations)) break;
        await document.ref.update({retentionNextAt: deferUntil,
          updatedAt: budget.now()});
        budget.writes++;
        counts.changed++;
        if (protectedReceipt) counts.protected++;
      } else {
        if (budget.writes >= (budget.maxWrites ??
            QUEUE_POLICY.cleanupMaxOperations)) break;
        await document.ref.delete();
        budget.writes++;
        counts.changed++;
      }
    } catch (error) {
      counts.failed++;
      console.error("[lookbook-record-cleanup] brand receipt deferred", {
        requestID: document.id,
        errorCode: error instanceof Error ? error.message : "unknown",
      });
      if (budget.writes < (budget.maxWrites ??
          QUEUE_POLICY.cleanupMaxOperations)) {
        await document.ref.update({retentionNextAt: deferUntil,
          updatedAt: budget.now()});
        budget.writes++;
        counts.changed++;
      }
    }
  }
}

async function cleanupRecoveryAudits(
  firestore: Firestore,
  queue: FirebaseFirestore.DocumentData | undefined,
  budget: WorkBudget,
  counts: RetentionCounts,
): Promise<void> {
  const candidates = await firestore.collectionGroup("recoveryDecisions")
    .where("expiresAt", "<=", budget.now())
    .orderBy("expiresAt")
    .limit(QUEUE_POLICY.cleanupPageSize).get();
  if (candidates.empty) return;
  budget.pages++;
  for (const document of candidates.docs) {
    if (!hasWriteBudget(budget)) break;
    counts.scanned++;
    const batchRef = document.ref.parent.parent;
    const batchID = batchRef?.id ?? null;
    try {
      const batch = batchRef ? (await batchRef.get()).data() : undefined;
      const protectedAudit = batchID !== null &&
        (queue?.headBatchID === batchID || batch?.state === "recoveryRequired");
      if (protectedAudit) {
        if (budget.writes >= (budget.maxWrites ??
            QUEUE_POLICY.cleanupMaxOperations)) break;
        await document.ref.update({expiresAt:
          budget.now() + QUEUE_POLICY.recordCleanupIntervalMs});
        budget.writes++;
        counts.changed++;
        counts.protected++;
      } else {
        if (budget.writes >= (budget.maxWrites ??
            QUEUE_POLICY.cleanupMaxOperations)) break;
        await document.ref.delete();
        budget.writes++;
        counts.changed++;
      }
    } catch (error) {
      counts.failed++;
      console.error("[lookbook-record-cleanup] recovery audit deferred", {
        auditPath: document.ref.path,
        errorCode: error instanceof Error ? error.message : "unknown",
      });
      if (budget.writes < (budget.maxWrites ??
          QUEUE_POLICY.cleanupMaxOperations)) {
        await document.ref.update({expiresAt:
          budget.now() + QUEUE_POLICY.recordCleanupIntervalMs});
        budget.writes++;
        counts.changed++;
      }
    }
  }
}

async function cleanupFailureRecords(
  firestore: Firestore, budget: WorkBudget, counts: RetentionCounts,
) {
  for (const collection of ["seasonImportFailures", "seasonImportFailureActions"]) {
    if (!hasBudget(budget)) break;
    const page = await firestore.collectionGroup(collection)
      .where("expiresAt", "<=", budget.now()).orderBy("expiresAt")
      .limit(QUEUE_POLICY.cleanupPageSize).get();
    if (page.empty) continue;
    budget.pages++;
    for (const document of page.docs) {
      if (!hasWriteBudget(budget)) break;
      counts.scanned++;
      try {
        const disposition = await firestore.runTransaction(async (tx) => {
          const snapshot = await tx.get(document.ref);
          const value = snapshot.data();
          if (!value || !Number.isSafeInteger(value.expiresAt) || value.expiresAt > budget.now()) return "unchanged";
          if (collection === "seasonImportFailures") {
            const brandRef = document.ref.parent.parent;
            let protect = value.state !== "failed";
            if (brandRef && typeof value.latestJobID === "string" &&
                typeof value.latestExecutionID === "string") {
              const execution = (await tx.get(brandRef.collection("importJobs")
                .doc(value.latestJobID).collection("executions").doc(value.latestExecutionID))).data();
              protect ||= Boolean(execution &&
                (!TERMINAL_EXECUTIONS.has(String(execution.status)) || execution.activeRunID != null));
            } else protect = true;
            if (protect) {
              tx.update(document.ref, {expiresAt: budget.now() + QUEUE_POLICY.recordCleanupIntervalMs});
              return "protected";
            }
          }
          tx.delete(document.ref);
          return "deleted";
        });
        if (disposition !== "unchanged") {
          budget.writes++;
          counts.changed++;
        }
        if (disposition === "protected") counts.protected++;
      } catch {
        counts.failed++;
      }
    }
  }
}

export async function cleanupLookbookQueueRecords(input: {
  firestore: Firestore;
  now?: () => number;
}): Promise<RetentionCounts> {
  const clock = input.now ?? Date.now;
  const start = clock();
  const owner = randomUUID();
  const counts: RetentionCounts = {scanned: 0, changed: 0, protected: 0,
    failed: 0, remaining: 0};
  if (!await claimLease(input.firestore, LEASE_PATH, owner, start)) return counts;
  const budget: WorkBudget = {pages: 0, writes: 0, startedAt: start, now: clock,
    maxPages: 3, maxWrites: 300};
  try {
    const queue = (await input.firestore.doc(QUEUE_PATH).get()).data();
    while (hasBudget(budget)) {
      const candidates = await input.firestore.collection(BATCH_COLLECTION)
        .where("retentionNextAt", "<=", clock())
        .orderBy("retentionNextAt")
        .limit(QUEUE_POLICY.cleanupPageSize).get();
      if (candidates.empty) break;
      budget.pages++;
      const changedBefore = budget.writes;
      for (const document of candidates.docs) {
        if (!hasWriteBudget(budget)) break;
        counts.scanned++;
        try {
          const before = budget.writes;
          await processBatchRetention(input.firestore, document, queue, budget);
          if (budget.writes > before) counts.changed += budget.writes - before;
          else counts.protected++;
        } catch (error) {
          counts.failed++;
          console.error("[lookbook-record-cleanup] batch deferred", {
            batchID: document.id,
            errorCode: error instanceof Error ? error.message : "unknown",
          });
          if (budget.writes < (budget.maxWrites ??
              QUEUE_POLICY.cleanupMaxOperations)) {
            await deferBatch(document.ref, clock(), budget);
            counts.changed++;
          }
        }
      }
      if (budget.writes === changedBefore) break;
    }
    budget.maxPages = 4;
    budget.maxWrites = 400;
    await cleanupBrandReceipts(input.firestore, queue, budget, counts);
    budget.maxPages = 5;
    budget.maxWrites = 500;
    await cleanupRecoveryAudits(input.firestore, queue, budget, counts);
    await cleanupFailureRecords(input.firestore, budget, counts);
    const [batches, brandReceipts, recoveryAudits, failures, failureActions] = await Promise.all([
      input.firestore.collection(BATCH_COLLECTION)
        .where("retentionNextAt", "<=", clock()).limit(1).get(),
      input.firestore.collection("brandCreationRequests")
        .where("retentionNextAt", "<=", clock()).limit(1).get(),
      input.firestore.collectionGroup("recoveryDecisions")
        .where("expiresAt", "<=", clock()).limit(1).get(),
      input.firestore.collectionGroup("seasonImportFailures")
        .where("expiresAt", "<=", clock()).limit(1).get(),
      input.firestore.collectionGroup("seasonImportFailureActions")
        .where("expiresAt", "<=", clock()).limit(1).get(),
    ]);
    counts.remaining = batches.size + brandReceipts.size + recoveryAudits.size +
      failures.size + failureActions.size;
    return counts;
  } finally {
    await releaseLease(input.firestore, LEASE_PATH, owner, clock());
  }
}

export const cleanupExpiredLookbookImportRecords = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Asia/Seoul",
    region: FUNCTIONS_REGION, timeoutSeconds: 540, memory: "512MiB",
    maxInstances: 1},
  async () => {
    const counts = await cleanupLookbookQueueRecords({firestore: db});
    console.info("[lookbook-record-cleanup] completed", counts);
  }
);
