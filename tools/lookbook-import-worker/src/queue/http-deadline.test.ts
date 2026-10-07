import assert from "node:assert/strict";
import test from "node:test";
import {waitForQueueBatchResponse, type QueueDeadlineResponse} from
  "./http-deadline.js";

test("14분 응답 기한은 재전달 응답을 보내고 drain 완료까지 기다린다", async () => {
  const controller = new AbortController();
  let statusCode: number | null = null;
  let body: unknown = null;
  let drained = false;
  const response: QueueDeadlineResponse = {
    headersSent: false,
    status(code) {
      statusCode = code;
      return this;
    },
    json(value) {
      body = value;
      this.headersSent = true;
    },
  };
  const operation = new Promise<string>((resolve) => {
    setTimeout(() => {
      drained = true;
      resolve("drained");
    }, 20);
  });
  const result = await waitForQueueBatchResponse({response, controller,
    operation, deadlineMs: 2});
  assert.equal(statusCode, 503);
  assert.deepEqual(body, {accepted: false, retryable: true,
    errorCode: "BATCH_DRAIN_DEADLINE_EXCEEDED"});
  assert.equal(controller.signal.aborted, true);
  assert.equal(result, "drained");
  assert.equal(drained, true);
});
