import assert from "node:assert/strict";
import test from "node:test";
import {canonicalJSON, queueBatchID, queueHash} from "./model.js";
import {isBatchQueueJob} from "./authorization.js";

test("PQ01 요청 digest는 객체 키 순서만 정규화하고 선택 순서를 보존한다", () => {
  assert.equal(queueHash({a: 1, b: ["x", "y"]}),
    queueHash({b: ["x", "y"], a: 1}));
  assert.notEqual(queueHash({a: 1, b: ["x", "y"]}),
    queueHash({a: 1, b: ["y", "x"]}));
  assert.notEqual(queueBatchID("one", "request"),
    queueBatchID("two", "request"));
  for (const value of [undefined, NaN, Infinity, new Date(), {a: undefined}]) {
    assert.throws(() => canonicalJSON(value), {message: "INVALID_CONTRACT"});
  }
});

test("PQ03 큐 소유 job은 불완전한 표식도 기존 전달 경로에서 제외한다", () => {
  assert.equal(isBatchQueueJob({status: "queued"}), false);
  for (const job of [{queueContractVersion: 1}, {queueContractVersion: 99},
    {queueBatchID: "one"}, {queueBatchID: null},
    {dispatchMode: "batchQueue"}]) {
    assert.equal(isBatchQueueJob(job), true);
  }
});
