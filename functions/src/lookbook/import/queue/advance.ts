/* eslint-disable require-jsdoc */
import type {Firestore} from "firebase-admin/firestore";
import {BATCH_COLLECTION, QUEUE_PATH, type QueueBatch} from "./model.js";

/**
 * 이미 released 된 head만 전진한다. 실행이 있었으면 명시적인 drain receipt가
 * 필요하며, 준비 단계에서 전부 중복/실패한 요청은 run 문서 없이 진행한다.
 * @param {Firestore} db queue database
 * @return {Promise<string | null>} 다음 head batch ID
 */
export async function advanceReleasedQueueHead(
  db: Firestore,
): Promise<string | null> {
  const queueRef = db.doc(QUEUE_PATH);
  return db.runTransaction(async (transaction) => {
    const queue = (await transaction.get(queueRef)).data();
    if (!queue || queue.state !== "idle" || queue.owner != null ||
        typeof queue.headBatchID !== "string") return null;
    const headRef = db.doc(`${BATCH_COLLECTION}/${queue.headBatchID}`);
    const head = (await transaction.get(headRef)).data() as
      QueueBatch | undefined;
    if (!head || head.state !== "released" || head.preparationOwner != null) {
      return null;
    }
    if (typeof head.runID === "string") {
      const run = (await transaction.get(
        headRef.collection("runs").doc(head.runID))).data();
      if (run?.terminalConfirmed !== true || run.inFlight !== 0) {
        throw new Error("QUEUE_DRAIN_UNCONFIRMED");
      }
    }
    const nextSequence = head.sequence + 1;
    const next = await transaction.get(db.collection(BATCH_COLLECTION)
      .where("sequence", "==", nextSequence).limit(2));
    if (next.size > 1) throw new Error("QUEUE_CORRUPT");
    if (next.empty && Number(queue.nextSequence) > nextSequence) {
      throw new Error("QUEUE_SEQUENCE_GAP");
    }
    const nextID = next.docs[0]?.id ?? null;
    transaction.update(queueRef, {headBatchID: nextID, state: "idle",
      owner: null, bootID: null, runID: null});
    return nextID;
  });
}
