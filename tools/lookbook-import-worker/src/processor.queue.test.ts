import assert from "node:assert/strict";
import test from "node:test";
import type {Firestore} from "firebase-admin/firestore";
import {processImportJobTaskRequest} from "./processor.js";

test("PQ10 구형 개별 task는 queue 소유 job을 claim하거나 갱신하지 않는다", async () => {
  const stored = {
    brandID: "brand-1",
    jobType: "importSeasonFromURL",
    sourceURL: "https://example.com/season",
    status: "queued",
    queueContractVersion: 1,
    queueBatchID: "b".repeat(64),
    queueExecutionID: "e".repeat(64),
    dispatchMode: "batchQueue",
  };
  let writes = 0;
  const ref = {
    collection(name: string) {
      return {doc: (id: string) => ({path: `brands/brand-1/${name}/${id}`})};
    },
  };
  const firestore = {
    collection: () => ({doc: () => ref}),
    runTransaction: async (operation: (transaction: unknown) => unknown) =>
      operation({
        get: async () => ({exists: true, data: () => stored}),
        update: () => {
          writes++;
        },
      }),
  } as unknown as Firestore;

  const result = await processImportJobTaskRequest({
    firestore,
    storage: {} as never,
    assetSyncConcurrency: 1,
  }, {brandID: "brand-1", jobID: "job-1", maxAttempts: 5}, 0);

  assert.deepEqual(result.result, {
    brandID: "brand-1", jobID: "job-1", processed: false,
    status: "skipped", reason: "queueExecutionRequired",
  });
  assert.equal(writes, 0);
});
