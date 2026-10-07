import assert from "node:assert/strict";
import test from "node:test";
import {isQueueOwnedJob} from "./ownership.js";

test("PQ10 부분 표식이 남은 queue job도 구형 경로에서 제외한다", () => {
  assert.equal(isQueueOwnedJob({status: "queued"}), false);
  for (const job of [
    {queueContractVersion: 1},
    {queueBatchID: "batch"},
    {queueExecutionID: "execution"},
    {dispatchMode: "batchQueue"},
    {queueActivationRequired: true},
  ]) {
    assert.equal(isQueueOwnedJob(job), true);
  }
});
