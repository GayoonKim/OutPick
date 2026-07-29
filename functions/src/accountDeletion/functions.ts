/* eslint-disable require-jsdoc, max-len */
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {firebaseAuth} from "../core/firebase.js";
import {AccountDeletionAuthContext} from "./contracts.js";
import {parseIntentInput, parseReceiptInput, requireRecentAuth} from "./policy.js";
import {
  cancelDeletion,
  createDeletionIntent,
  loadDeletionStatus,
  recordSessionRevocation,
  requestDeletion,
} from "./repository.js";

type CallableAuth = {
  uid: string;
  token: Record<string, unknown>;
} | undefined;

function stringClaim(
  token: Record<string, unknown>,
  key: string,
): string | null {
  const value = token[key];
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() : null;
}

export function deletionAuthContext(auth: CallableAuth): AccountDeletionAuthContext {
  if (!auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "로그인이 필요합니다.",
    );
  }
  const firebaseClaim = auth.token.firebase;
  const firebaseProvider = firebaseClaim &&
    typeof firebaseClaim === "object" &&
    !Array.isArray(firebaseClaim) ?
    stringClaim(firebaseClaim as Record<string, unknown>, "sign_in_provider") :
    null;
  const authTime = auth.token.auth_time;
  return {
    uid: auth.uid,
    authTimeSeconds: typeof authTime === "number" ? authTime : Number.NaN,
    provider: stringClaim(auth.token, "provider") ?? firebaseProvider ?? "unknown",
    providerUserID: stringClaim(auth.token, "providerUserID"),
  };
}

export async function handlePrepareAccountDeletion(
  auth: CallableAuth,
  nowMillis = Date.now(),
) {
  const context = deletionAuthContext(auth);
  requireRecentAuth(context, nowMillis);
  return createDeletionIntent(context, nowMillis);
}

export async function handleRequestAccountDeletion(
  auth: CallableAuth,
  data: unknown,
  nowMillis = Date.now(),
) {
  const context = deletionAuthContext(auth);
  requireRecentAuth(context, nowMillis);
  const result = await requestDeletion(context, parseIntentInput(data), nowMillis);
  try {
    await firebaseAuth.revokeRefreshTokens(context.uid);
    await recordSessionRevocation(result.requestID, true);
  } catch (error) {
    console.error("[requestAccountDeletion] session revoke failed", {
      requestID: result.requestID,
      code: (error as {code?: string})?.code,
    });
    await recordSessionRevocation(result.requestID, false);
  }
  return result;
}

export async function handleCancelAccountDeletion(
  auth: CallableAuth,
  nowMillis = Date.now(),
) {
  const context = deletionAuthContext(auth);
  requireRecentAuth(context, nowMillis);
  return cancelDeletion(context, nowMillis);
}

export async function handleGetAccountDeletionStatus(data: unknown) {
  const input = parseReceiptInput(data);
  return loadDeletionStatus(input.requestID, input.receiptToken);
}

const securedCallableOptions = {
  region: FUNCTIONS_REGION,
  enforceAppCheck: true,
};

export const prepareAccountDeletion = onCall(
  securedCallableOptions,
  async (request) => handlePrepareAccountDeletion(request.auth),
);

export const requestAccountDeletion = onCall(
  securedCallableOptions,
  async (request) => handleRequestAccountDeletion(request.auth, request.data),
);

export const cancelAccountDeletion = onCall(
  securedCallableOptions,
  async (request) => handleCancelAccountDeletion(request.auth),
);

export const getAccountDeletionStatus = onCall(
  securedCallableOptions,
  async (request) => handleGetAccountDeletionStatus(request.data),
);
