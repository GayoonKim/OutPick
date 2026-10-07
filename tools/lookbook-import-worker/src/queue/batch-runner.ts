/* eslint-disable require-jsdoc, max-len */
import type {Firestore} from "firebase-admin/firestore";
import {RetryableImportError} from "../import-error.js";
import {PipelineRuntime} from "../pipeline/resources.js";
import {
  advanceReleasedHead, beginBatchDrain, claimBatch, finishBatchRun,
  parseBatchDelivery,
  isQueueExecutionTerminal,
  type BatchDelivery, type BatchOwnership, type BatchRunContext,
} from "./coordinator.js";
import {beginBatchItemAttempt, finishBatchItemAttempt} from "./checkpoint.js";
import {
  createQueuePipelineRuntime, runQueueBatchItems,
  type BatchItemResult,
} from "./runtime.js";
import {QueueSupervisor} from "./supervisor.js";
import {browserImageGate} from "./browser-gate.js";
import {QUEUE_ADMISSION_STATUSES, QUEUE_POLICY} from "./contracts.js";
import {prepareSeasonRestart} from "./restart.js";

type BatchItem = {
  itemID: string;
  ordinal: number;
  admissionStatus: string;
  jobID: string | null;
  executionID: string | null;
  processingStatus?: unknown;
};

export type QueueImportResult = {
  status: "succeeded" | "partialFailed" | "failed" | "awaitingReview" |
    "correctionRequired" | "cancelled";
};

export type QueueAttemptContext = {
  brandID: string;
  batchKind: string;
  item: BatchItem;
  ownership: BatchOwnership;
  attempt: number;
  attemptID: string;
  attemptLimit: number;
  mode: string | null;
  input: Record<string, unknown> | null;
  pipeline: PipelineRuntime;
};

export type QueueBatchResult = {
  accepted: true;
  status: "notClaimed" | "unsupported" | "released" | "queued" |
    "recoveryRequired";
  batchID: string;
  nextBatchID?: string | null;
  completedItemCount?: number;
  notStartedItemCount?: number;
  reason?: string;
  resourceEvidence?: ReturnType<QueueSupervisor["snapshot"]>;
};

const SUPPORTED_KINDS = ["importSeasons", "discoverSeasons", "assetRetry",
  "reviewApproval", "manualRetry", "repair"] as const;
const ADMISSION_STATUSES = new Set<string>(QUEUE_ADMISSION_STATUSES);

// 모든 접수 kind는 하나의 실행권·자원 감독·종료 확인 경계를 공유한다.
export async function processImportSeasonsBatch(
  db: Firestore,
  rawDelivery: unknown,
  owner: string,
  bootID: string,
  admissionSignal: AbortSignal,
  executeAttempt: (context: QueueAttemptContext) => Promise<QueueImportResult>,
  clock: () => number = Date.now,
  createSupervisor: () => QueueSupervisor = () => new QueueSupervisor(),
  runContext?: BatchRunContext,
  readRestartMetadata?: Parameters<typeof prepareSeasonRestart>[0]["readMetadata"],
): Promise<QueueBatchResult> {
  const delivery: BatchDelivery = parseBatchDelivery(rawDelivery);
  const batchRef = db.doc(`lookbookImportBatches/${delivery.batchID}`);
  const beforeClaim = (await batchRef.get()).data();
  if (!beforeClaim) {
    return {accepted: true, status: "notClaimed", batchID: delivery.batchID};
  }
  if (!SUPPORTED_KINDS.includes(beforeClaim.kind as typeof SUPPORTED_KINDS[number])) {
    return {accepted: true, status: "unsupported", batchID: delivery.batchID,
      reason: "BATCH_KIND_NOT_CONNECTED"};
  }
  if (beforeClaim.state === "released") {
    const nextBatchID = await advanceReleasedHead(db);
    return {accepted: true, status: "released", batchID: delivery.batchID,
      nextBatchID};
  }

  const claimedAt = clock();
  const ownership = await claimBatch(db, delivery, owner, bootID, claimedAt,
    SUPPORTED_KINDS, runContext);
  if (!ownership) {
    return {accepted: true, status: "notClaimed", batchID: delivery.batchID};
  }

  const batch = (await batchRef.get()).data();
  if (!batch || !SUPPORTED_KINDS.includes(
    batch.kind as typeof SUPPORTED_KINDS[number]) ||
      typeof batch.brandID !== "string" || !batch.brandID ||
      !Array.isArray(batch.items) ||
      batch.items.length > QUEUE_POLICY.maxSelectedSeasons) {
    return await finishRecovery(db, ownership, "QUEUE_BATCH_CORRUPT", clock());
  }
  const items = batch.items as BatchItem[];
  const created: Array<{ordinal: number; value: BatchItem}> = [];
  for (let ordinal = 0; ordinal < items.length; ordinal++) {
    const item = items[ordinal];
    if (!item || typeof item !== "object" ||
        item.ordinal !== ordinal || typeof item.itemID !== "string" ||
        !item.itemID || !ADMISSION_STATUSES.has(item.admissionStatus) ||
        item.admissionStatus === "created" &&
          (typeof item.jobID !== "string" || typeof item.executionID !== "string")) {
      return await finishRecovery(db, ownership, "QUEUE_ITEM_CORRUPT", clock());
    }
    if (item.admissionStatus === "created") created.push({ordinal, value: item});
  }

  // 이 신호는 새 시즌 투입만 막는다. 현재 시즌은 끝까지 await하고 drain한다.
  const stopForRecovery = new AbortController();
  const supervisor = created.length > 0 ? createSupervisor() : null;
  const signals = [admissionSignal, stopForRecovery.signal];
  if (supervisor) signals.push(supervisor.signal);
  const runSignal = AbortSignal.any(signals);
  const pipeline = createQueuePipelineRuntime(runSignal);
  const unregisterBufferCleanup = pipeline.sourceBuffers ?
    browserImageGate.registerBrowserTransitionCleanup(() =>
      pipeline.sourceBuffers?.clearRetained()) : () => undefined;
  let recoveryReason: string | null = null;
  let scheduled: BatchItemResult<BatchItem, void>[];
  try {
    scheduled = await runQueueBatchItems(created,
      async (item, ordinal) => {
        try {
          // 재개 시 이미 종료한 항목은 보존한다. release transaction에서 실제 execution 종료도 재확인한다.
          if (isQueueExecutionTerminal(item.processingStatus)) return;
          const execution = (await db.doc(`brands/${batch.brandID}/importJobs/${String(item.jobID)}/executions/${String(item.executionID)}`).get()).data();
          if (execution?.restartFromParsing === true &&
              Number(execution.attemptCount) >= Number(execution.attemptLimit)) {
            await prepareSeasonRestart({firestore: db, ownership, ordinal,
              jobID: String(item.jobID), executionID: String(item.executionID),
              readMetadata: readRestartMetadata, now: clock()});
          }
          const begun = await beginBatchItemAttempt(db, ownership, {
            ordinal, jobID: String(item.jobID), executionID: String(item.executionID),
          }, clock());
          if (!begun.started) {
            if (begun.reason === "attemptsExhausted") return;
            recoveryReason = `QUEUE_ITEM_${begun.reason.toUpperCase()}`;
            stopForRecovery.abort(new Error(recoveryReason));
            return;
          }

          const batchKind = begun.batchKind;

          let attempt = begun;
          for (;;) {
            try {
              const result = await executeAttempt({brandID: batch.brandID,
                batchKind, item, ownership,
                attempt: attempt.attempt, attemptID: attempt.attemptID,
                attemptLimit: attempt.attemptLimit, mode: attempt.mode, input: attempt.input,
                pipeline});
              const outcome = result.status;
              await finishBatchItemAttempt(db, ownership, {
                ordinal, jobID: String(item.jobID),
                executionID: String(item.executionID), outcome,
              }, clock());
              return;
            } catch (error) {
              if (error instanceof RetryableImportError &&
                  attempt.attempt < attempt.attemptLimit) {
                const now = clock();
                await finishBatchItemAttempt(db, ownership, {
                  ordinal, jobID: String(item.jobID),
                  executionID: String(item.executionID), outcome: "retryWaiting",
                  retryAt: now, errorCode: "RETRYABLE_IMPORT_ERROR",
                }, now);
                if (batchKind !== "discoverSeasons" &&
                    ["importSeasons", "manualRetry", "reviewApproval"].includes(batchKind)) {
                  await prepareSeasonRestart({firestore: db, ownership, ordinal,
                    jobID: String(item.jobID), executionID: String(item.executionID),
                    forNextAttempt: true, readMetadata: readRestartMetadata, now});
                }
                const next = await beginBatchItemAttempt(db, ownership, {
                  ordinal, jobID: String(item.jobID),
                  executionID: String(item.executionID),
                }, clock());
                if (next.started) {
                  attempt = next;
                  continue;
                }
                if (next.reason === "attemptsExhausted") return;
                recoveryReason = `QUEUE_ITEM_${next.reason.toUpperCase()}`;
                stopForRecovery.abort(new Error(recoveryReason));
                return;
              }
              const now = clock();
              if (error instanceof RetryableImportError) {
                if (["importSeasons", "manualRetry", "reviewApproval"].includes(batchKind)) {
                  await prepareSeasonRestart({firestore: db, ownership, ordinal,
                    jobID: String(item.jobID), executionID: String(item.executionID),
                    readMetadata: readRestartMetadata, now});
                }
                await finishBatchItemAttempt(db, ownership, {
                  ordinal, jobID: String(item.jobID), executionID: String(item.executionID),
                  outcome: "failed", errorCode: "ATTEMPTS_EXHAUSTED",
                }, now);
                return;
              }
              await finishBatchItemAttempt(db, ownership, {
                ordinal, jobID: String(item.jobID),
                executionID: String(item.executionID), outcome: "recoveryRequired",
                errorCode: error instanceof RetryableImportError ?
                  "RETRY_LIMIT_EXECUTOR_ERROR" : "QUEUE_ITEM_EXECUTOR_ERROR",
              }, now);
              recoveryReason = "QUEUE_ITEM_EXECUTOR_ERROR";
              stopForRecovery.abort(new Error(recoveryReason));
              return;
            }
          }
        } catch (_error) {
          recoveryReason ??= "QUEUE_ITEM_CHECKPOINT_ERROR";
          stopForRecovery.abort(new Error(recoveryReason));
        }
      }, {signal: runSignal});
  } finally {
    unregisterBufferCleanup();
  }

  await beginBatchDrain(db, ownership, clock());
  const snapshot = pipeline.snapshot() as Record<string,
    {active: number; queued: number}>;
  const sourceSnapshot = pipeline.sourceBuffers?.snapshot();
  const resourcesDrained = Object.values(snapshot).every((value) =>
    value.active === 0 && value.queued === 0) &&
    sourceSnapshot?.openScopes === 0 && sourceSnapshot.retainedBytes === 0;
  const notStartedItemCount = scheduled.filter((result) =>
    result.status === "notStarted").length;
  const failedScheduleCount = scheduled.filter((result) =>
    result.status === "failed").length;
  const resourceEvidence = supervisor?.stop();
  if (resourceEvidence?.memoryStop) {
    recoveryReason ??= `QUEUE_${resourceEvidence.memoryStop.replaceAll(":", "_").toUpperCase()}`;
  }
  const disposition = recoveryReason || failedScheduleCount || !resourcesDrained ?
    "recovery" as const : notStartedItemCount > 0 ? "continue" as const :
    "complete" as const;
  let finalState: string;
  try {
    finalState = await finishBatchRun(db, ownership, {
      disposition, drained: resourcesDrained,
      inFlight: 0,
      ...(recoveryReason ? {reason: recoveryReason} :
        !resourcesDrained ? {reason: "RESOURCE_DRAIN_UNCONFIRMED"} : {}),
      ...(resourceEvidence ? {resourceEvidence} : {}),
    }, clock());
  } catch (error) {
    if (disposition !== "complete") throw error;
    return await finishRecovery(db, ownership,
      error instanceof Error && error.message === "QUEUE_EXECUTION_NOT_TERMINAL" ?
        "QUEUE_EXECUTION_NOT_TERMINAL" : "QUEUE_COMPLETION_UNCONFIRMED",
      clock(), resourceEvidence);
  }
  if (finalState === "recoveryRequired") {
    return {accepted: true, status: "recoveryRequired", batchID: delivery.batchID,
      completedItemCount: scheduled.filter((result) =>
        result.status === "completed").length,
      notStartedItemCount, reason: recoveryReason ?? "QUEUE_RECOVERY_REQUIRED",
      ...(resourceEvidence ? {resourceEvidence} : {})};
  }
  if (finalState === "released") {
    const nextBatchID = await advanceReleasedHead(db);
    return {accepted: true, status: "released", batchID: delivery.batchID,
      nextBatchID,
      completedItemCount: scheduled.filter((result) =>
        result.status === "completed").length,
      notStartedItemCount, ...(resourceEvidence ? {resourceEvidence} : {})};
  }
  return {accepted: true, status: "queued", batchID: delivery.batchID,
    completedItemCount: scheduled.filter((result) =>
      result.status === "completed").length,
    notStartedItemCount, ...(resourceEvidence ? {resourceEvidence} : {})};
}

async function finishRecovery(
  db: Firestore, ownership: BatchOwnership, reason: string, now: number,
  resourceEvidence?: ReturnType<QueueSupervisor["snapshot"]>,
): Promise<QueueBatchResult> {
  await beginBatchDrain(db, ownership, now);
  const state = await finishBatchRun(db, ownership, {
    disposition: "recovery", drained: false, inFlight: 1, reason,
    ...(resourceEvidence ? {resourceEvidence} : {}),
  }, now);
  return {
    accepted: true,
    status: state === "recoveryRequired" ? "recoveryRequired" : "queued",
    batchID: ownership.batchID,
    reason,
    ...(resourceEvidence ? {resourceEvidence} : {}),
  };
}
