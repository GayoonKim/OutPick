/* eslint-disable require-jsdoc, max-len */
import type {DocumentReference, Transaction} from "firebase-admin/firestore";
import {readOwnedBatch, type BatchOwnership} from "./coordinator.js";

export type JobWriteOwnership = {
  ownership: BatchOwnership; ordinal: number; executionID: string;
};

// 실행권 검사와 root/시즌 쓰기를 같은 transaction에 넣는다.
export async function assertJobWriteOwnership(
  tx: Transaction, ref: DocumentReference, context: JobWriteOwnership,
) {
  const batch = await readOwnedBatch(ref.firestore, tx, context.ownership);
  const item = (batch.items as Array<Record<string, unknown>>)[context.ordinal];
  const [root, execution] = await Promise.all([
    tx.get(ref), tx.get(ref.collection("executions").doc(context.executionID)),
  ]);
  if (!item || item.jobID !== ref.id || item.executionID !== context.executionID ||
      item.processingStatus !== "active" ||
      root.data()?.queueExecutionID !== context.executionID ||
      root.data()?.queueActiveRunID !== context.ownership.runID ||
      execution.data()?.activeRunID !== context.ownership.runID) {
    throw new Error("QUEUE_JOB_WRITE_OWNERSHIP_LOST");
  }
}

export async function updateOwnedJob(
  ref: DocumentReference, context: JobWriteOwnership | undefined,
  patch: Record<string, unknown>,
) {
  if (!context) {
    await ref.update(patch);
    return;
  }
  await ref.firestore.runTransaction(async (tx) => {
    await assertJobWriteOwnership(tx, ref, context);
    tx.update(ref, patch);
  });
}

export async function updateOwnedTarget(
  job: DocumentReference, context: JobWriteOwnership | undefined,
  target: DocumentReference, patch: Record<string, unknown>,
) {
  if (!context) {
    await target.set(patch, {merge: true});
    return;
  }
  await job.firestore.runTransaction(async (tx) => {
    await assertJobWriteOwnership(tx, job, context);
    if (!(await tx.get(target)).exists) throw new Error("QUEUE_ASSET_TARGET_MISSING");
    tx.update(target, patch);
  });
}
