/* eslint-disable require-jsdoc */

export type QueueDeadlineResponse = {
  headersSent: boolean;
  status(code: number): QueueDeadlineResponse;
  json(body: unknown): unknown;
};

// 응답 기한을 넘긴 작업은 503으로 재전달시키되, 호출자가 drain 결과를
// 기다리게 해 늦은 실행을 성공·종료로 잘못 확정하지 않는다.
export async function waitForQueueBatchResponse<T>(input: {
  response: QueueDeadlineResponse;
  controller: AbortController;
  operation: Promise<T>;
  deadlineMs: number;
}): Promise<T> {
  if (!Number.isSafeInteger(input.deadlineMs) || input.deadlineMs < 1) {
    throw new Error("INVALID_QUEUE_RESPONSE_DEADLINE");
  }
  const timer = setTimeout(() => {
    if (!input.response.headersSent) {
      input.response.status(503).json({accepted: false, retryable: true,
        errorCode: "BATCH_DRAIN_DEADLINE_EXCEEDED"});
    }
    input.controller.abort(new Error("BATCH_DRAIN_DEADLINE_EXCEEDED"));
  }, input.deadlineMs);
  timer.unref();
  try {
    return await input.operation;
  } finally {
    clearTimeout(timer);
  }
}
