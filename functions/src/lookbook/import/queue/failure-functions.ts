/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import type {Firestore} from "firebase-admin/firestore";
import {db} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {recordData, requiredAuthUID} from "../../../core/callable.js";
import {admitSeasonImportFailureRetry, dismissSeasonImportFailure as dismiss,
  listSeasonImportFailures} from "./failure-service.js";

function callable(service: (firestore: Firestore, uid: string,
  data: Record<string, unknown>) => Promise<unknown>) {
  return onCall({region: FUNCTIONS_REGION}, async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    try {
      return await service(db, uid, recordData(request.data));
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (["INVALID_CONTRACT", "CLOCK_INVALID"].includes(code)) {
        throw new HttpsError("invalid-argument", code);
      }
      if (code === "PERMISSION_DENIED") {
        throw new HttpsError("permission-denied", code);
      }
      if (["REQUEST_NOT_FOUND", "TARGET_DELETED"].includes(code)) {
        throw new HttpsError("not-found", code);
      }
      if (["SNAPSHOT_STALE", "REQUEST_EXPIRED", "REQUEST_ID_CONFLICT"]
        .includes(code)) {
        throw new HttpsError("failed-precondition", code);
      }
      throw new HttpsError("internal", "실패한 시즌의 요청을 처리하지 못했습니다.");
    }
  });
}

export const getSeasonImportFailures = callable(listSeasonImportFailures);
export const requestSeasonImportFailureRetry =
  callable(admitSeasonImportFailureRetry);
export const dismissSeasonImportFailure = callable(dismiss);
