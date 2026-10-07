/* eslint-disable require-jsdoc */
import type {Firestore} from "firebase-admin/firestore";
import {BATCH_COLLECTION, QUEUE_PATH, type QueueBatch} from "./model.js";
import {QUEUE_POLICY} from "./contracts.js";

export type BatchDispatchIntent = {
  taskID: string;
  endpoint: "/tasks/import-batch";
  dispatchDeadlineSeconds: number;
  payload: {batchID: string; dispatchGeneration: number;
    queueContractVersion: 1};
};

export async function deliverQueueHead(
  db: Firestore,
  send: (intent: BatchDispatchIntent) => Promise<void>,
  now = Date.now()
): Promise<boolean> {
  const intent = await db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(db.doc(QUEUE_PATH))).data();
    if (!queue?.headBatchID || queue.state === "recoveryRequired") return null;
    const batchID = String(queue.headBatchID);
    const batch = (await transaction.get(db.doc(
      `${BATCH_COLLECTION}/${batchID}`))).data() as QueueBatch | undefined;
    if (!batch || batch.state !== "queued" ||
        batch.dispatchState !== "pending") return null;
    return {
      taskID: `batch-${batchID}-${batch.dispatchGeneration}`,
      endpoint: "/tasks/import-batch" as const,
      dispatchDeadlineSeconds: QUEUE_POLICY.externalDeadlineMs / 1000,
      payload: {batchID, dispatchGeneration: batch.dispatchGeneration,
        queueContractVersion: 1 as const},
    };
  });
  if (!intent) return false;
  // 같은 taskID의 already-exists는 송신 adapter에서 성공으로 취급한다.
  // 영속 intent는 송신 성공 후에만 확정하며 응답 유실 때 같은 ID로 재전송한다.
  await send(intent);
  const ref = db.doc(`${BATCH_COLLECTION}/${intent.payload.batchID}`);
  await db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(db.doc(QUEUE_PATH))).data();
    const batch = (await transaction.get(ref)).data() as QueueBatch | undefined;
    if (!batch || queue?.headBatchID !== intent.payload.batchID ||
        batch.dispatchGeneration !== intent.payload.dispatchGeneration ||
        batch.dispatchState !== "pending" || batch.state !== "queued") return;
    transaction.update(ref, {
      dispatchState: "delivered", dispatchDeliveredAt: now,
      dispatchDeliveryCount: Number(batch.dispatchDeliveryCount ?? 0) + 1,
      stateRevision: batch.stateRevision + 1, updatedAt: now,
    });
  });
  return true;
}

/**
 * Cloud Tasks가 실행을 claim하기 전에 배달이 사라졌을 때 같은 task ID를
 * 재전달해도 안전한 시점인지 판정한다. 이 함수는 작업 종료를 추론하지 않는다.
 * @param {QueueBatch} batch 전달할 batch
 * @param {number} now 현재 시각
 * @return {boolean} 동일 task ID 재전달이 허용되면 true
 */
export function isQueueDispatchStale(
  batch: Pick<QueueBatch, "state" | "dispatchState"> & {
    dispatchDeliveredAt?: unknown;
  }, now: number,
): boolean {
  if (!Number.isSafeInteger(now) || now < 0 || batch.state !== "queued" ||
      batch.dispatchState !== "delivered" ||
      !Number.isSafeInteger(batch.dispatchDeliveredAt) ||
      Number(batch.dispatchDeliveredAt) < 0) return false;
  return now - Number(batch.dispatchDeliveredAt) >=
    QUEUE_POLICY.externalDeadlineMs;
}

/**
 * 현재 head가 queued 상태인데 15분 동안 Worker가 claim하지 못한 경우,
 * 같은 dispatch generation으로 idempotent task 전달을 다시 허용한다.
 * @param {Firestore} db queue와 batch 문서
 * @param {number} now 현재 시각
 * @return {Promise<boolean>} 전달 재개 여부
 */
export async function reopenStaleQueueDispatch(
  db: Firestore, now = Date.now(),
): Promise<boolean> {
  const queueRef = db.doc(QUEUE_PATH);
  return db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(queueRef)).data();
    if (!queue || queue.state !== "idle" || queue.owner != null ||
        typeof queue.headBatchID !== "string") return false;
    const batchRef = db.doc(`${BATCH_COLLECTION}/${queue.headBatchID}`);
    const batch = (await transaction.get(batchRef)).data() as
      QueueBatch | undefined;
    if (!batch || !isQueueDispatchStale(batch, now)) return false;
    transaction.update(batchRef, {
      dispatchState: "pending", dispatchReopenedAt: now,
      stateRevision: batch.stateRevision + 1, updatedAt: now,
    });
    return true;
  });
}
