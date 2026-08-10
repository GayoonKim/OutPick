/* eslint-disable require-jsdoc, max-len */
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requiredAuthUID} from "../../core/callable.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import {
  parseSubmitRoomReportInput,
  parseSubmitUserReportInput,
} from "./contracts.js";
import {
  submitRoomReportService,
  submitUserReportService,
} from "./service.js";

const securedCallableOptions = {
  region: FUNCTIONS_REGION,
  enforceAppCheck: true,
};

export async function handleSubmitUserReport(authUID: string | undefined, data: unknown) {
  const uid = requiredAuthUID(authUID);
  await assertAccountCapability(uid, "report");
  return submitUserReportService(uid, parseSubmitUserReportInput(data));
}

export async function handleSubmitRoomReport(authUID: string | undefined, data: unknown) {
  const uid = requiredAuthUID(authUID);
  await assertAccountCapability(uid, "report");
  return submitRoomReportService(uid, parseSubmitRoomReportInput(data));
}

function callableError(error: unknown, operation: string): never {
  if (error instanceof HttpsError) throw error;
  console.error(`[${operation}] unexpected error`, error);
  throw new HttpsError("internal", "신고 요청을 처리하지 못했습니다.");
}

export const submitUserReport = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleSubmitUserReport(request.auth?.uid, request.data);
    } catch (error) {
      return callableError(error, "submitUserReport");
    }
  },
);

export const submitRoomReport = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleSubmitRoomReport(request.auth?.uid, request.data);
    } catch (error) {
      return callableError(error, "submitRoomReport");
    }
  },
);
