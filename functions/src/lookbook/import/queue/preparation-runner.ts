/* eslint-disable require-jsdoc */
import {randomUUID} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {BATCH_COLLECTION, QUEUE_PATH, type QueueBatch} from "./model.js";
import {
  beginQueuePreparation, finishQueuePreparation, prepareQueueItem,
} from "./preparation.js";

export async function prepareNextQueueBatch(db: Firestore) {
  const queue = (await db.doc(QUEUE_PATH).get()).data();
  if (!queue || queue.state === "recoveryRequired") return null;
  const candidates = await db.collection(BATCH_COLLECTION)
    .where("sequence", "==", queue.preparationSequence).limit(2).get();
  if (candidates.empty) return null;
  if (candidates.size !== 1) throw new Error("QUEUE_CORRUPT");
  const snapshot = candidates.docs[0];
  const batch = snapshot.data() as QueueBatch;
  if (batch.state !== "preparing" || batch.preparationOwner) return null;
  // 아직 접수 adapter를 연결하지 않은 종류를 잘못 준비하지 않는다.
  if (!["importSeasons", "discoverSeasons", "assetRetry", "reviewApproval",
    "manualRetry", "repair"].includes(batch.kind)) {
    return null;
  }
  const owner = randomUUID();
  try {
    if (!await beginQueuePreparation(db, snapshot.id, owner)) return null;
  } catch (error) {
    if (error instanceof Error && error.message === "PREPARATION_BUSY") {
      return null;
    }
    throw error;
  }
  const errors: {ordinal: number; code: string}[] = [];
  // 같은 batch를 갱신하는 transaction 간 재시도 경쟁을 피한다.
  for (const item of batch.items) {
    if (item.admissionStatus !== "pending") continue;
    try {
      await prepareQueueItem(db, snapshot.id, item.ordinal, owner);
    } catch (error) {
      errors.push({ordinal: item.ordinal,
        code: error instanceof Error ? error.message : "PREPARATION_ERROR"});
    }
  }
  // 모든 시작한 작업의 응답을 받은 뒤 owner를 해제한다. 늦은 commit은
  // item transaction의 owner 조건과 같은 batch 쓰기 충돌로 차단된다.
  await db.runTransaction(async (transaction) => {
    const current = (await transaction.get(snapshot.ref)).data();
    if (current?.preparationOwner !== owner) {
      throw new Error("PREPARATION_OWNER");
    }
    transaction.set(snapshot.ref.collection("preparationAttempts")
      .doc(String(current.preparationAttempts)), {
      owner, errors, finishedAt: Date.now(),
    });
  });
  return finishQueuePreparation(db, snapshot.id, owner);
}
