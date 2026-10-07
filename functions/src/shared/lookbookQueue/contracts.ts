// 브랜드 생성과 룩북 접수가 공유하는 제품 큐 계약. 실험 계약과 분리한다.
export const QUEUE_CONTRACT_VERSION = 1;
export const QUEUE_POLICY = Object.freeze({
  maxSelectedSeasons: 80,
  seasonConcurrency: 6,
  downloadConcurrency: 4,
  transformConcurrency: 1,
  uploadConcurrency: 4,
  sourceReuseBytes: 134217728,
  browserConcurrency: 1,
  stopAdmissionAfterMs: 720000,
  drainTargetAfterMs: 840000,
  externalDeadlineMs: 900000,
  memoryLimitPercent: 85,
  memorySustainedMs: 1000,
  memorySampleMs: 100,
  memoryMaxGapMs: 500,
  importAttempts: 5,
  discoveryAttempts: 3,
  preparationAttempts: 5,
  noProgressSegments: 2,
  processingPollMs: 3000,
  waitingPollMs: 10000,
  pollErrorInitialMs: 10000,
  pollErrorSecondMs: 20000,
  pollErrorThirdMs: 40000,
  pollErrorMaxMs: 60000,
  reconcileIntervalMs: 300000,
  fileCleanupIntervalMs: 3600000,
  recordCleanupIntervalMs: 86400000,
  cleanupPageSize: 100,
  cleanupMaxPages: 5,
  cleanupMaxOperations: 500,
  cleanupAdmissionMs: 120000,
  newRequestMaxAgeMs: 86400000,
  newRequestMaxFutureMs: 300000,
  unreferencedFileRetentionMs: 86400000,
  successDetailRetentionMs: 86400000,
  receiptRetentionMs: 2592000000,
  resolvedFailureRetentionMs: 2592000000,
  recoveryAuditRetentionMs: 7776000000,
  localSettledRetentionMs: 2592000000,
});
export const QUEUE_BATCH_STATES = [
  "preparing",
  "queued",
  "active",
  "draining",
  "retryWaiting",
  "recoveryRequired",
  "released",
] as const;
export const QUEUE_ADMISSION_STATUSES =
  ["pending", "created", "duplicate", "failed", "skipped"] as const;
export const QUEUE_ERROR_CODES = [
  "INVALID_CONTRACT",
  "REQUEST_EXPIRED",
  "CLOCK_INVALID",
  "REQUEST_ID_CONFLICT",
  "SNAPSHOT_STALE",
  "PERMISSION_DENIED",
  "TARGET_DELETED",
] as const;

export type QueueBatchState = typeof QUEUE_BATCH_STATES[number];
export type QueueContractError = typeof QUEUE_ERROR_CODES[number];
export type QueueRequestEnvelope = {
  queueContractVersion: typeof QUEUE_CONTRACT_VERSION;
  requestID: string;
  requestCreatedAt: number;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const parseQueueRequestEnvelope = (
  input: unknown
): QueueRequestEnvelope => {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("INVALID_CONTRACT");
  }
  const value = input as Record<string, unknown>;
  if (value.queueContractVersion !== QUEUE_CONTRACT_VERSION ||
      typeof value.requestID !== "string" ||
      value.requestID.length !== 36 ||
      !uuidPattern.test(value.requestID) ||
      typeof value.requestCreatedAt !== "number" ||
      !Number.isSafeInteger(value.requestCreatedAt) ||
      value.requestCreatedAt < 0) {
    throw new Error("INVALID_CONTRACT");
  }
  return {
    queueContractVersion: QUEUE_CONTRACT_VERSION,
    requestID: value.requestID,
    requestCreatedAt: value.requestCreatedAt,
  };
};

// 기존 영수증 조회/동일 payload 대조 후, 영수증이 없는 신규 접수에만 호출한다.
export const newQueueAdmissionTimeError = (
  requestCreatedAt: number,
  now: number
): "REQUEST_EXPIRED" | "CLOCK_INVALID" | null => {
  if (!Number.isSafeInteger(now) || now < 0 ||
      !Number.isSafeInteger(requestCreatedAt) || requestCreatedAt < 0) {
    throw new Error("INVALID_CONTRACT");
  }
  if (now - requestCreatedAt > QUEUE_POLICY.newRequestMaxAgeMs) {
    return "REQUEST_EXPIRED";
  }
  if (requestCreatedAt - now > QUEUE_POLICY.newRequestMaxFutureMs) {
    return "CLOCK_INVALID";
  }
  return null;
};

export const parseQueueBatchState = (input: unknown): QueueBatchState => {
  if (typeof input !== "string" ||
      !QUEUE_BATCH_STATES.includes(input as QueueBatchState)) {
    throw new Error("INVALID_CONTRACT");
  }
  return input as QueueBatchState;
};
