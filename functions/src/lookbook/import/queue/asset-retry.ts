/* eslint-disable require-jsdoc */
import {queueDocumentID, queueHash} from "./model.js";

export function assetRetrySource(data: Record<string, unknown>) {
  if (data.jobType !== "importSeasonFromURL" ||
      !["failed", "partialFailed"].includes(String(data.status)) ||
      typeof data.sourceURL !== "string" ||
      !/^https?:\/\//.test(data.sourceURL) ||
      !Array.isArray(data.createdPostIDs) ||
      data.createdPostIDs.length < 1 || data.createdPostIDs.length > 120) {
    throw new Error("ASSET_RETRY_NOT_ALLOWED");
  }
  const targetSeasonID = queueDocumentID(data.targetSeasonID);
  const createdPostIDs = [...new Set(data.createdPostIDs.map(queueDocumentID))];
  const sourceURL = data.sourceURL;
  // heartbeat 같은 비본질 필드는 재시도 입력 변경으로 취급하지 않는다.
  const sourceDigest = queueHash({
    status: data.status, targetSeasonID, createdPostIDs, sourceURL,
    queueExecutionID: data.queueExecutionID ?? null,
    assetRetryRequestID: data.assetRetryRequestID ?? null,
  });
  return {sourceDigest, sourceURL, targetSeasonID, createdPostIDs};
}
