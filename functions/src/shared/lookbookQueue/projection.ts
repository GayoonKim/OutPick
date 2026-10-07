/* eslint-disable require-jsdoc */
import type {QueueBatch} from "./model.js";

export function projectQueueReceipt(batchID: string, batch: QueueBatch) {
  const items = batch.items.map((item) => ({
    itemID: item.itemID,
    targetID: item.targetID,
    ordinal: item.ordinal,
    admissionStatus: item.admissionStatus,
    processingStatus: item.processingStatus ?? null,
    jobID: item.jobID,
    executionID: item.executionID,
    errorCode: item.errorCode,
  }));
  const count = (status: string) =>
    items.filter((item) => item.admissionStatus === status).length;
  const processingCount = (statuses: string[]) =>
    items.filter((item) => item.admissionStatus === "created" &&
      statuses.includes(String(item.processingStatus))).length;
  return {
    contractVersion: batch.contractVersion,
    requestID: batch.requestID,
    batchID,
    brandID: batch.brandID,
    kind: batch.kind,
    receiptState: batch.state,
    stateRevision: batch.stateRevision,
    items,
    requestedCount: items.length,
    pendingCount: count("pending"),
    createdCount: count("created"),
    duplicateCount: count("duplicate"),
    failedCount: count("failed"),
    skippedCount: count("skipped"),
    executionSucceededCount: processingCount(["succeeded"]),
    executionFailedCount: processingCount(["failed", "partialFailed"]),
    executionReviewCount: processingCount([
      "awaitingReview", "correctionRequired",
    ]),
  };
}
