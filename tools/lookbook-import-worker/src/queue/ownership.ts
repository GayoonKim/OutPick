/* eslint-disable require-jsdoc */

// 일부 필드만 남았어도 제품 큐 job을 구형 실행 경로로 돌려보내지 않는다.
export function isQueueOwnedJob(input: object): boolean {
  const data = input as Record<string, unknown>;
  return data.queueContractVersion !== undefined ||
    data.queueBatchID !== undefined ||
    data.queueExecutionID !== undefined ||
    data.dispatchMode === "batchQueue" ||
    data.queueActivationRequired === true;
}
