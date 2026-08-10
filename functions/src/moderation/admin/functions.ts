/* eslint-disable require-jsdoc, max-len */
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requiredAuthUID} from "../../core/callable.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {assertAccountCapability} from "../../shared/accountStatus.js";
import {
  parseGetModerationReportDetailInput,
  parseListModerationReportsInput,
  parseMutateAccountModerationInput,
  parseMutateModerationReviewInput,
  requireRecentAdminAuth,
} from "./contracts.js";
import {
  assertActivePlatformAdmin,
  consumeAdminRateLimit,
  getModerationReportDetailService,
  listModerationReportsService,
  mutateAccountModerationService,
  mutateModerationReviewService,
} from "./service.js";

type CallableAuth = {
  uid: string;
  token: Record<string, unknown>;
} | undefined;

const securedCallableOptions = {
  region: FUNCTIONS_REGION,
  enforceAppCheck: true,
};

async function activeAdminUID(auth: CallableAuth): Promise<string> {
  const uid = requiredAuthUID(auth?.uid);
  await assertAccountCapability(uid, "readAppContent");
  await assertActivePlatformAdmin(uid);
  return uid;
}

export async function handleListModerationReports(auth: CallableAuth, data: unknown) {
  const uid = await activeAdminUID(auth);
  await consumeAdminRateLimit(uid, "read");
  return listModerationReportsService(parseListModerationReportsInput(data));
}

export async function handleGetModerationReportDetail(auth: CallableAuth, data: unknown) {
  const uid = await activeAdminUID(auth);
  await consumeAdminRateLimit(uid, "read");
  return getModerationReportDetailService(parseGetModerationReportDetailInput(data));
}

export async function handleMutateModerationReview(auth: CallableAuth, data: unknown) {
  const uid = await activeAdminUID(auth);
  await consumeAdminRateLimit(uid, "mutation");
  return mutateModerationReviewService(uid, parseMutateModerationReviewInput(data));
}

export async function handleMutateAccountModeration(
  auth: CallableAuth,
  data: unknown,
  now = new Date(),
) {
  const uid = await activeAdminUID(auth);
  requireRecentAdminAuth(auth?.token.auth_time, now);
  await consumeAdminRateLimit(uid, "mutation", now);
  return mutateAccountModerationService(
    uid,
    parseMutateAccountModerationInput(data),
    now,
  );
}

function callableError(error: unknown, operation: string): never {
  if (error instanceof HttpsError) throw error;
  console.error(`[${operation}] unexpected error`, error);
  throw new HttpsError("internal", "관리자 신고 작업을 처리하지 못했습니다.");
}

export const listModerationReports = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleListModerationReports(request.auth, request.data);
    } catch (error) {
      return callableError(error, "listModerationReports");
    }
  },
);

export const getModerationReportDetail = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleGetModerationReportDetail(request.auth, request.data);
    } catch (error) {
      return callableError(error, "getModerationReportDetail");
    }
  },
);

export const mutateModerationReview = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleMutateModerationReview(request.auth, request.data);
    } catch (error) {
      return callableError(error, "mutateModerationReview");
    }
  },
);

export const mutateAccountModeration = onCall(
  securedCallableOptions,
  async (request) => {
    try {
      return await handleMutateAccountModeration(request.auth, request.data);
    } catch (error) {
      return callableError(error, "mutateAccountModeration");
    }
  },
);
