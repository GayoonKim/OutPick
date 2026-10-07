/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {db} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {recordData, requiredAuthUID} from "../../../core/callable.js";
import {parseQueueRequestEnvelope} from "./contracts.js";
import {getQueueReceipt, getQueueReceiptByBatchID} from "./admission.js";
import {queueAuthorization} from "./authorization.js";

export const getSeasonImportBatch = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const input = recordData(request.data);
    try {
      if (Object.keys(input).some((key) =>
        !["requestID", "batchID"].includes(key)) ||
        ((input.requestID !== undefined) === (input.batchID !== undefined))) {
        throw new Error("INVALID_CONTRACT");
      }
      const authorize = queueAuthorization(db);
      if (input.batchID !== undefined) {
        if (typeof input.batchID !== "string" ||
            !/^[a-f0-9]{64}$/.test(input.batchID)) {
          throw new Error("INVALID_CONTRACT");
        }
        return await getQueueReceiptByBatchID(
          db, uid, input.batchID, authorize);
      }
      const envelope = parseQueueRequestEnvelope({
        requestID: input.requestID,
        queueContractVersion: 1, requestCreatedAt: 0,
      });
      return await getQueueReceipt(db, uid, envelope.requestID, authorize);
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (code === "INVALID_CONTRACT") {
        throw new HttpsError("invalid-argument", code);
      }
      if (code === "PERMISSION_DENIED") {
        throw new HttpsError("permission-denied", code);
      }
      if (code === "REQUEST_NOT_FOUND" || code === "TARGET_DELETED") {
        throw new HttpsError("not-found", code);
      }
      throw new HttpsError("internal", "접수 상태를 확인하지 못했습니다.");
    }
  }
);
